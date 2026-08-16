import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/services/loyalty/loyalty_point_value.dart';

void main() {
  group('LoyaltyPointValue', () {
    test('displays one cent as 0.01 major currency units', () {
      expect(LoyaltyPointValue.toInputText(1), '0.01');
    });

    test('parses dot and comma decimal separators into exact cents', () {
      expect(LoyaltyPointValue.fromInputText('0.01'), 1);
      expect(LoyaltyPointValue.fromInputText('0,25'), 25);
      expect(LoyaltyPointValue.fromInputText('1.50'), 150);
    });

    test('never stores a zero or sub-cent point value', () {
      expect(LoyaltyPointValue.fromInputText('0'), 1);
      expect(LoyaltyPointValue.fromInputText('0.001'), 1);
      expect(LoyaltyPointValue.fromInputText('invalid'), 1);
    });
  });
}
