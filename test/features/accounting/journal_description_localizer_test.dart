import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/accounting/presentation/utils/journal_description_localizer.dart';

void main() {
  late Map<String, dynamic> arabic;

  setUpAll(() {
    arabic =
        jsonDecode(File('assets/translations/ar.json').readAsStringSync())
            as Map<String, dynamic>;
  });

  String resolve(String key, List<String> args) {
    dynamic value = arabic;
    for (final part in key.split('.')) {
      value = (value as Map<String, dynamic>)[part];
    }
    var result = value as String;
    for (final arg in args) {
      result = result.replaceFirst('{}', arg);
    }
    return result;
  }

  test('uses the localized fallback only when no description exists', () {
    expect(
      localizedJournalDescription(null, resolver: resolve),
      'سطر المعاملة',
    );
  });

  test('localizes return settlement and reversal descriptions', () {
    expect(
      localizedJournalDescription(
        'Cash refund — Sale Return #4',
        resolver: resolve,
      ),
      'رد نقدي — مرتجع بيع #4',
    );
    expect(
      localizedJournalDescription(
        'REVERSAL: Inventory decreased — Purchase Return #3',
        resolver: resolve,
      ),
      'عكس: تخفيض المخزون — مرتجع شراء #3',
    );
  });

  test('localizes document headers while preserving user-entered reasons', () {
    expect(
      localizedJournalDescription(
        'Purchase #7 — Credit + VAT',
        resolver: resolve,
      ),
      'شراء #7 — آجل + ضريبة',
    );
    expect(
      localizedJournalDescription(
        'Inventory Gain #2 — لا اعلم',
        resolver: resolve,
      ),
      'زيادة مخزون #2 — لا اعلم',
    );
  });

  test('the three locales expose the same journal-description keys', () {
    Set<String> keys(String locale) {
      final json =
          jsonDecode(
                File('assets/translations/$locale.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      return (json['journal_descriptions'] as Map<String, dynamic>).keys
          .toSet();
    }

    expect(keys('en'), keys('ar'));
    expect(keys('fr'), keys('ar'));
  });
}
