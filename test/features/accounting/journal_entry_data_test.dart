import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/accounting/domain/models/journal_entry_data.dart';

void main() {
  group('JournalEntryData', () {
    test('creates valid simple entry', () {
      final entry = JournalEntryData.simple(
        description: 'Test sale',
        debitAccountId: 1,
        creditAccountId: 2,
        amountCents: 1000,
        currencyId: 1,
      );

      expect(entry.isValid, isTrue);
      expect(entry.lines.length, equals(2));
      expect(entry.totalDebitCents, equals(1000));
      expect(entry.totalCreditCents, equals(1000));
    });

    test('validates balanced entry', () {
      final entry = JournalEntryData(
        description: 'Multi-line entry',
        lines: [
          JournalEntryLineData(
            accountId: 1,
            debitCents: 500,
            creditCents: 0,
            currencyId: 1,
          ),
          JournalEntryLineData(
            accountId: 2,
            debitCents: 500,
            creditCents: 0,
            currencyId: 1,
          ),
          JournalEntryLineData(
            accountId: 3,
            debitCents: 0,
            creditCents: 1000,
            currencyId: 1,
          ),
        ],
      );

      expect(entry.isValid, isTrue);
      expect(entry.totalDebitCents, equals(1000));
      expect(entry.totalCreditCents, equals(1000));
    });

    test('detects unbalanced entry', () {
      final entry = JournalEntryData(
        description: 'Unbalanced entry',
        lines: [
          JournalEntryLineData(
            accountId: 1,
            debitCents: 1000,
            creditCents: 0,
            currencyId: 1,
          ),
          JournalEntryLineData(
            accountId: 2,
            debitCents: 0,
            creditCents: 500,
            currencyId: 1,
          ),
        ],
      );

      expect(entry.isValid, isFalse);
      final errors = entry.validate();
      expect(errors.any((e) => e.contains('must equal')), isTrue);
    });

    test('detects empty description', () {
      final entry = JournalEntryData(
        description: '',
        lines: [
          JournalEntryLineData(
            accountId: 1,
            debitCents: 1000,
            creditCents: 0,
            currencyId: 1,
          ),
          JournalEntryLineData(
            accountId: 2,
            debitCents: 0,
            creditCents: 1000,
            currencyId: 1,
          ),
        ],
      );

      expect(entry.isValid, isFalse);
      final errors = entry.validate();
      expect(errors.any((e) => e.contains('Description')), isTrue);
    });

    test('detects insufficient lines', () {
      final entry = JournalEntryData(
        description: 'Single line',
        lines: [
          JournalEntryLineData(
            accountId: 1,
            debitCents: 1000,
            creditCents: 0,
            currencyId: 1,
          ),
        ],
      );

      expect(entry.isValid, isFalse);
      final errors = entry.validate();
      expect(errors.any((e) => e.contains('at least 2 lines')), isTrue);
    });
  });

  group('JournalEntryLineData', () {
    test('validates debit line', () {
      final line = JournalEntryLineData(
        accountId: 1,
        debitCents: 1000,
        creditCents: 0,
        currencyId: 1,
      );

      expect(line.isValid, isTrue);
      expect(line.isDebit, isTrue);
      expect(line.isCredit, isFalse);
      expect(line.amountCents, equals(1000));
    });

    test('validates credit line', () {
      final line = JournalEntryLineData(
        accountId: 1,
        debitCents: 0,
        creditCents: 1000,
        currencyId: 1,
      );

      expect(line.isValid, isTrue);
      expect(line.isDebit, isFalse);
      expect(line.isCredit, isTrue);
      expect(line.amountCents, equals(1000));
    });

    test('rejects line with both debit and credit', () {
      final line = JournalEntryLineData(
        accountId: 1,
        debitCents: 500,
        creditCents: 500,
        currencyId: 1,
      );

      expect(line.isValid, isFalse);
      final errors = line.validate();
      expect(errors.any((e) => e.contains('both debit and credit')), isTrue);
    });

    test('rejects line with zero amounts', () {
      final line = JournalEntryLineData(
        accountId: 1,
        debitCents: 0,
        creditCents: 0,
        currencyId: 1,
      );

      expect(line.isValid, isFalse);
      final errors = line.validate();
      expect(errors.any((e) => e.contains('either debit or credit')), isTrue);
    });

    test('rejects negative debit', () {
      final line = JournalEntryLineData(
        accountId: 1,
        debitCents: -1000,
        creditCents: 0,
        currencyId: 1,
      );

      expect(line.isValid, isFalse);
      final errors = line.validate();
      expect(errors.any((e) => e.contains('negative')), isTrue);
    });

    test('rejects negative credit', () {
      final line = JournalEntryLineData(
        accountId: 1,
        debitCents: 0,
        creditCents: -1000,
        currencyId: 1,
      );

      expect(line.isValid, isFalse);
      final errors = line.validate();
      expect(errors.any((e) => e.contains('negative')), isTrue);
    });

    test('rejects invalid account ID', () {
      final line = JournalEntryLineData(
        accountId: 0,
        debitCents: 1000,
        creditCents: 0,
        currencyId: 1,
      );

      expect(line.isValid, isFalse);
      final errors = line.validate();
      expect(errors.any((e) => e.contains('Account ID')), isTrue);
    });

    test('rejects invalid currency ID', () {
      final line = JournalEntryLineData(
        accountId: 1,
        debitCents: 1000,
        creditCents: 0,
        currencyId: 0,
      );

      expect(line.isValid, isFalse);
      final errors = line.validate();
      expect(errors.any((e) => e.contains('Currency ID')), isTrue);
    });
  });
}
