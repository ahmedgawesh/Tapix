import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/auth/presentation/utils/audit_log_localizer.dart';

void main() {
  late Map<String, dynamic> arabicAudit;

  setUpAll(() {
    final json =
        jsonDecode(File('assets/translations/ar.json').readAsStringSync())
            as Map<String, dynamic>;
    arabicAudit = json['audit'] as Map<String, dynamic>;
  });

  String resolve(String key) {
    final name = key.substring('audit.'.length);
    return arabicAudit[name]?.toString() ?? key;
  }

  test('localizes cheque audit entities and lifecycle actions', () {
    expect(
      localizedAuditEntityType('cheque_instrument', resolver: resolve),
      'شيك',
    );
    expect(localizedAuditAction('clear', resolver: resolve), 'تحصيل');
    expect(localizedAuditAction('bounce', resolver: resolve), 'تسجيل ارتداد');
    expect(
      localizedAuditAction('remote_sale_return_created', resolver: resolve),
      'إنشاء مرتجع بيع عبر الشبكة',
    );
  });

  test('localizes nested audit change names and status values', () {
    final text = formatLocalizedAuditChanges({
      'severity': 'critical',
      'old': {'status': 'received'},
      'new': {'status': 'cleared', 'paymentId': 232},
    }, resolver: resolve);

    expect(text, contains('الأهمية: حرج'));
    expect(text, contains('قبل:'));
    expect(text, contains('الحالة: مستلم'));
    expect(text, contains('بعد:'));
    expect(text, contains('الحالة: محصّل'));
    expect(text, contains('معرف الدفعة: 232'));
  });

  test('all supported locales expose the same audit label keys', () {
    Set<String> keys(String locale) {
      final json =
          jsonDecode(
                File('assets/translations/$locale.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      return (json['audit'] as Map<String, dynamic>).keys
          .where(
            (key) =>
                key.startsWith('entity_') ||
                key.startsWith('action_') ||
                key.startsWith('change_') ||
                key.startsWith('value_'),
          )
          .toSet();
    }

    expect(keys('en'), keys('ar'));
    expect(keys('fr'), keys('ar'));
  });
}
