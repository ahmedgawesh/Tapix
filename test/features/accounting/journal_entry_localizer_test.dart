import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/accounting/presentation/utils/journal_entry_localizer.dart';

void main() {
  late Map<String, dynamic> arabicAccounting;

  setUpAll(() {
    final json =
        jsonDecode(File('assets/translations/ar.json').readAsStringSync())
            as Map<String, dynamic>;
    arabicAccounting = json['accounting'] as Map<String, dynamic>;
  });

  String resolve(String key) {
    final name = key.substring('accounting.'.length);
    return arabicAccounting[name]?.toString() ?? key;
  }

  test('localizes cheque, return, and source-table labels', () {
    expect(
      localizedJournalEntryType('cheque_clearance', resolver: resolve),
      'مقاصة شيك',
    );
    expect(
      localizedJournalEntryType('purchase_return', resolver: resolve),
      'مرتجع مشتريات',
    );
    expect(
      localizedJournalSourceTable('cheque_instruments', resolver: resolve),
      'شيك',
    );
  });

  test('uses a readable fallback instead of exposing a translation key', () {
    expect(
      localizedJournalEntryType('future_entry', resolver: resolve),
      'Future entry',
    );
  });

  test('all supported locales expose the same entry type and source keys', () {
    Set<String> keys(String locale) {
      final json =
          jsonDecode(
                File('assets/translations/$locale.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      return (json['accounting'] as Map<String, dynamic>).keys
          .where((key) => key.startsWith('type_') || key.startsWith('source_'))
          .toSet();
    }

    expect(keys('en'), keys('ar'));
    expect(keys('fr'), keys('ar'));
  });
}
