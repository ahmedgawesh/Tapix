/// Exception thrown for accounting-related errors
class AccountingException implements Exception {
  final String message;
  final String? code;
  final dynamic details;

  AccountingException(this.message, {this.code, this.details});

  @override
  String toString() => 'AccountingException: $message';
}

/// Exception thrown when journal entry is unbalanced
class UnbalancedEntryException extends AccountingException {
  final int totalDebits;
  final int totalCredits;

  UnbalancedEntryException({
    required this.totalDebits,
    required this.totalCredits,
  }) : super(
         'Journal entry unbalanced: Debits=$totalDebits, Credits=$totalCredits',
         code: 'UNBALANCED_ENTRY',
       );

  int get difference => totalDebits - totalCredits;
}

/// Exception thrown when trying to modify a posted entry
class ImmutableEntryException extends AccountingException {
  final int entryId;

  ImmutableEntryException(this.entryId)
    : super(
        'Cannot modify posted journal entry: $entryId',
        code: 'IMMUTABLE_ENTRY',
      );
}

/// Exception thrown when accounting period is closed
class ClosedPeriodException extends AccountingException {
  final int periodId;

  ClosedPeriodException(this.periodId)
    : super('Accounting period is closed: $periodId', code: 'CLOSED_PERIOD');
}

/// Exception thrown when account is not found
class AccountNotFoundException extends AccountingException {
  final int? accountId;
  final String? accountCode;

  AccountNotFoundException({this.accountId, this.accountCode})
    : super(
        'Account not found: ${accountId ?? accountCode}',
        code: 'ACCOUNT_NOT_FOUND',
      );
}

/// Exception thrown when validation fails
class ValidationException extends AccountingException {
  final List<String> errors;

  ValidationException(this.errors)
    : super(
        'Validation failed: ${errors.join(", ")}',
        code: 'VALIDATION_FAILED',
        details: errors,
      );
}

/// Exception thrown when reconciliation fails
class ReconciliationException extends AccountingException {
  final List<String> issues;

  ReconciliationException(this.issues)
    : super(
        'Reconciliation failed: ${issues.length} issues found',
        code: 'RECONCILIATION_FAILED',
        details: issues,
      );
}
