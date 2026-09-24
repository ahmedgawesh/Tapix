/// Data class for creating journal entries
/// Used by AccountingRepository.createJournalEntry()
class JournalEntryData {
  final String description;
  final DateTime? entryDate;
  final int? accountingPeriodId;
  final String? entryType;
  final String? sourceTable;
  final int? sourceId;
  final int? reversedEntryId;
  final List<JournalEntryLineData> lines;
  final bool autoPost;

  JournalEntryData({
    required this.description,
    this.entryDate,
    this.accountingPeriodId,
    this.entryType,
    this.sourceTable,
    this.sourceId,
    this.reversedEntryId,
    required this.lines,
    this.autoPost = false,
  });

  /// Create a simple two-line entry (most common case)
  factory JournalEntryData.simple({
    required String description,
    required int debitAccountId,
    required int creditAccountId,
    required int amountCents,
    required int currencyId,
    DateTime? entryDate,
    String? entryType,
    String? sourceTable,
    int? sourceId,
    bool autoPost = true,
  }) {
    return JournalEntryData(
      description: description,
      entryDate: entryDate,
      entryType: entryType,
      sourceTable: sourceTable,
      sourceId: sourceId,
      autoPost: autoPost,
      lines: [
        JournalEntryLineData(
          accountId: debitAccountId,
          debitCents: amountCents,
          creditCents: 0,
          currencyId: currencyId,
        ),
        JournalEntryLineData(
          accountId: creditAccountId,
          debitCents: 0,
          creditCents: amountCents,
          currencyId: currencyId,
        ),
      ],
    );
  }

  /// Validate the entry data
  List<String> validate() {
    final errors = <String>[];

    if (description.isEmpty) {
      errors.add('Description is required');
    }

    if (lines.isEmpty) {
      errors.add('At least one line is required');
    }

    if (lines.length < 2) {
      errors.add('Journal entry must have at least 2 lines');
    }

    int totalDebits = 0;
    int totalCredits = 0;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineErrors = line.validate();
      for (final error in lineErrors) {
        errors.add('Line ${i + 1}: $error');
      }
      totalDebits += line.debitCents;
      totalCredits += line.creditCents;
    }

    if (totalDebits != totalCredits) {
      errors.add('Debits ($totalDebits) must equal Credits ($totalCredits)');
    }

    return errors;
  }

  /// Check if entry is valid
  bool get isValid => validate().isEmpty;

  /// Get total debits
  int get totalDebitCents =>
      lines.fold(0, (sum, line) => sum + line.debitCents);

  /// Get total credits
  int get totalCreditCents =>
      lines.fold(0, (sum, line) => sum + line.creditCents);
}

/// Data class for journal entry lines
class JournalEntryLineData {
  final int accountId;
  final int debitCents;
  final int creditCents;
  final int currencyId;
  final String? description;

  JournalEntryLineData({
    required this.accountId,
    required this.debitCents,
    required this.creditCents,
    required this.currencyId,
    this.description,
  });

  /// Validate the line data
  List<String> validate() {
    final errors = <String>[];

    if (accountId <= 0) {
      errors.add('Account ID is required');
    }

    if (debitCents < 0) {
      errors.add('Debit cannot be negative');
    }

    if (creditCents < 0) {
      errors.add('Credit cannot be negative');
    }

    if (debitCents > 0 && creditCents > 0) {
      errors.add('Cannot have both debit and credit');
    }

    if (debitCents == 0 && creditCents == 0) {
      errors.add('Must have either debit or credit');
    }

    if (currencyId <= 0) {
      errors.add('Currency ID is required');
    }

    return errors;
  }

  /// Check if line is valid
  bool get isValid => validate().isEmpty;

  /// Check if this is a debit line
  bool get isDebit => debitCents > 0;

  /// Check if this is a credit line
  bool get isCredit => creditCents > 0;

  /// Get the amount (whichever is non-zero)
  int get amountCents => debitCents > 0 ? debitCents : creditCents;
}
