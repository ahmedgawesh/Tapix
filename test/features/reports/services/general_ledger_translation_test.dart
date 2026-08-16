import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

dynamic _nested(Map<String, dynamic> json, String first, String second) {
  final section = json[first] as Map<String, dynamic>;
  return section[second];
}

void main() {
  test('general ledger entry number header uses a translated key', () {
    for (final locale in ['ar', 'en', 'fr']) {
      final json =
          jsonDecode(
                File('assets/translations/$locale.json').readAsStringSync(),
              )
              as Map<String, dynamic>;

      expect(
        _nested(json, 'accounting', 'entry_number'),
        isA<String>().having((value) => value.trim(), 'value', isNotEmpty),
        reason: 'Missing accounting.entry_number in $locale translations',
      );
    }

    final source = File(
      'lib/features/reports/presentation/screens/general_ledger_screen.dart',
    ).readAsStringSync();

    expect(source, contains("'accounting.entry_number'.tr()"));
    expect(source, isNot(contains("'reports.entry_number'.tr()")));
  });
}
