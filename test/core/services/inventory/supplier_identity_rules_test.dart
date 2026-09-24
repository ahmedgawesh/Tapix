import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/services/inventory/supplier_identity_rules.dart';

void main() {
  group('supplier code normalization', () {
    for (final entry in {
      'N': 'N',
      'n': 'N',
      ' N ': 'N',
      'n1': 'N1',
      'ALN2026': 'ALN2026',
      '007': '007',
      'abc123': 'ABC123',
      'ABCDEFGHIJ12': 'ABCDEFGHIJ12',
    }.entries) {
      test('${entry.key} -> ${entry.value}', () {
        expect(
          SupplierIdentityRules.normalizeSupplierCode(entry.key),
          entry.value,
        );
      });
    }
    test('many suppliers may have no code', () {
      for (final code in [null, '', '   ']) {
        expect(SupplierIdentityRules.normalizeSupplierCode(code), isNull);
      }
    });
    for (final code in [
      'N 1',
      'N-1',
      'N_1',
      'ABCDEFGHIJKLM',
      'نور',
      'N١',
      'A\u0000B',
      'A\nB',
      'N🙂',
      'ß',
      'é',
      'Ａ',
      'N\u200B1',
    ]) {
      test('rejects unsupported code ${code.codeUnits}', () {
        expect(
          () => SupplierIdentityRules.normalizeSupplierCode(code),
          throwsA(
            isA<SupplierIdentityException>().having(
              (e) => e.messageKey,
              'key',
              'supplier_identity.invalid_code',
            ),
          ),
        );
      });
    }
  });

  group('source SKU construction', () {
    test('alphanumeric prefix and leading zeros are preserved', () {
      expect(
        SupplierIdentityRules.composeSourceSku(
          supplierCode: 'n1',
          baseSku: '015',
        ),
        'N1-015',
      );
      expect(
        SupplierIdentityRules.composeSourceSku(
          supplierCode: '007',
          baseSku: '0015',
        ),
        '007-0015',
      );
    });
    test('base SKU can distinguish colors and sizes', () {
      expect(
        SupplierIdentityRules.composeSourceSku(
          supplierCode: 'N1',
          baseSku: '015-BL_S/1',
        ),
        'N1-015-BL_S/1',
      );
    });
    test('cannot overlap old TR receipt-code namespace', () {
      expect(
        () => SupplierIdentityRules.composeSourceSku(
          supplierCode: 'TR',
          baseSku: List.filled(32, 'A').join(),
        ),
        throwsA(isA<SupplierIdentityException>()),
      );
    });
    test('base code is required and never guessed', () {
      expect(
        () => SupplierIdentityRules.validateBaseSku(null),
        throwsA(isA<SupplierIdentityException>()),
      );
      expect(
        () => SupplierIdentityRules.validateBaseSku(''),
        throwsA(isA<SupplierIdentityException>()),
      );
    });
    test('does not silently strip unsupported characters', () {
      expect(
        () => SupplierIdentityRules.validateBaseSku('A 015'),
        throwsA(isA<SupplierIdentityException>()),
      );
      expect(
        () => SupplierIdentityRules.validateBaseSku('صنف015'),
        throwsA(isA<SupplierIdentityException>()),
      );
    });
    test('unrelated errors are not disguised as code conflicts', () {
      expect(
        SupplierIdentityException.fromError(StateError('disk full')),
        isNull,
      );
    });
  });
}
