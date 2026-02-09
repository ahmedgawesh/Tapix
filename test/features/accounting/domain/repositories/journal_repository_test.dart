import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/accounting/domain/repositories/journal_repository.dart';

void main() {
  group('JournalLineInput', () {
    test('should create JournalLineInput with required fields', () {
      final line = JournalLineInput(
        accountId: 1,
        debitCents: Decimal.fromInt(1000),
        creditCents: Decimal.zero,
        currencyId: 1,
      );

      expect(line.accountId, 1);
      expect(line.debitCents, Decimal.fromInt(1000));
      expect(line.creditCents, Decimal.zero);
      expect(line.currencyId, 1);
      expect(line.description, isNull);
    });

    test('should create JournalLineInput with optional description', () {
      final line = JournalLineInput(
        accountId: 2,
        debitCents: Decimal.zero,
        creditCents: Decimal.fromInt(500),
        currencyId: 1,
        description: 'Test line',
      );

      expect(line.description, 'Test line');
    });
  });
}
