import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/services/pharmacy/medicine_normalization_service.dart';

void main() {
  const service = MedicineNormalizationService();

  group('MedicineNormalizationService', () {
    test('normalizes Arabic marks and equivalent letter forms', () {
      expect(
        service.normalizeIngredientName('  إِيبُوبْرُوفِين - صوديوم  '),
        'ايبوبروفين صوديوم',
      );
      expect(
        service.normalizeIngredientName('Paracetamol   Sodium'),
        'paracetamol sodium',
      );
    });

    test('normalizes equivalent mass strengths without floating point', () {
      final grams = service.normalizeStrength(value: '0.4', unit: 'g');
      final milligrams = service.normalizeStrength(value: '400', unit: 'mg');
      final arabicDigits = service.normalizeStrength(
        value: '٠٫٤',
        unit: 'جرام',
      );

      expect(grams.valueMicros, 400000000);
      expect(grams.unit, 'mg');
      expect(grams.equivalentTo(milligrams), isTrue);
      expect(arabicDigits.equivalentTo(milligrams), isTrue);
    });

    test('compares equivalent concentration ratios exactly', () {
      final perFive = service.normalizeStrength(
        value: '100',
        unit: 'mg',
        basisValue: '5',
        basisUnit: 'ml',
      );
      final perOne = service.normalizeStrength(
        value: '0.02',
        unit: 'g',
        basisValue: '0.001',
        basisUnit: 'l',
      );

      expect(perFive.equivalentTo(perOne), isTrue);
      expect(
        perFive.equivalentTo(
          service.normalizeStrength(
            value: '25',
            unit: 'mg',
            basisValue: '1',
            basisUnit: 'ml',
          ),
        ),
        isFalse,
      );
    });

    test('supports micrograms and international units', () {
      final micrograms = service.normalizeStrength(value: '500', unit: 'µg');
      final milligrams = service.normalizeStrength(value: '0.5', unit: 'mg');
      final internationalUnits = service.normalizeStrength(
        value: '1000',
        unit: 'وحدة دولية',
      );

      expect(micrograms.equivalentTo(milligrams), isTrue);
      expect(internationalUnits.unit, 'iu');
      expect(internationalUnits.valueMicros, 1000000000);
    });

    test('rejects incomplete, unsupported and imprecise strengths', () {
      expect(
        () => service.normalizeStrength(
          value: '100',
          unit: 'mg',
          basisValue: '5',
        ),
        throwsA(
          isA<PharmacyValidationException>().having(
            (error) => error.code,
            'code',
            'strength_basis_incomplete',
          ),
        ),
      );
      expect(
        () => service.normalizeStrength(value: '-1', unit: 'mg'),
        throwsA(isA<PharmacyValidationException>()),
      );
      expect(
        () => service.normalizeStrength(value: '1', unit: 'unknown'),
        throwsA(isA<PharmacyValidationException>()),
      );
      expect(
        () => service.normalizeStrength(value: '0.0000001', unit: 'ng'),
        throwsA(
          isA<PharmacyValidationException>().having(
            (error) => error.code,
            'code',
            'strength_precision_exceeded',
          ),
        ),
      );
    });

    test('normalizes canonical form and route codes', () {
      expect(
        service.normalizeCode('Oral Suspension', field: 'dosage_form'),
        'oral_suspension',
      );
      expect(
        service.normalizeCode('INTRA-VENOUS', field: 'route'),
        'intra_venous',
      );
    });

    test('converts stored fixed-point values back to editable decimals', () {
      expect(service.editableValue(500000), '0.5');
      expect(service.editableValue(12000000), '12');
      expect(service.editableValue(1234567), '1.234567');
    });
  });
}
