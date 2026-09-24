import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/services/lan/lan_business_models.dart';

void main() {
  test('older supplier JSON without productCode still loads', () {
    final s = LanSupplierSummary.fromJson({
      'id': 1,
      'name': 'Noor',
      'phone': null,
    });
    expect(s.productCode, isNull);
    expect(s.toJson(), {'id': 1, 'name': 'Noor', 'phone': null});
  });

  test(
    'alphanumeric supplier code round-trips without a second reservation',
    () {
      const s = LanSupplierSummary(id: 1, name: 'Noor', productCode: 'ALN2026');
      expect(LanSupplierSummary.fromJson(s.toJson()).productCode, 'ALN2026');
    },
  );

  test('numeric-looking code remains text with leading zeroes', () {
    const s = LanSupplierSummary(id: 1, name: 'Noor', productCode: '007');
    expect(LanSupplierSummary.fromJson(s.toJson()).productCode, '007');
  });
}
