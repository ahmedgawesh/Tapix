import 'package:decimal/decimal.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/repositories/journal_repository.dart';

/// Events for JournalEntryFormBloc
abstract class JournalEntryFormEvent extends RealtimeEvent {
  const JournalEntryFormEvent();
}

class JournalEntryFormLoadRequested extends JournalEntryFormEvent {
  final int? entryId;
  const JournalEntryFormLoadRequested({this.entryId});
}

class JournalEntryFormSubmitRequested extends JournalEntryFormEvent {
  final String description;
  final DateTime entryDate;
  final List<JournalLineInput> lines;
  final int? createdBy;

  const JournalEntryFormSubmitRequested({
    required this.description,
    required this.entryDate,
    required this.lines,
    this.createdBy,
  });
}

/// State data for journal entry form
class JournalEntryFormData {
  final JournalEntry? existingEntry;
  final List<JournalEntryLine> existingLines;
  final List<Account> availableAccounts;
  final bool isSubmitting;
  final bool isSubmitted;
  final String? errorMessage;

  const JournalEntryFormData({
    this.existingEntry,
    this.existingLines = const [],
    this.availableAccounts = const [],
    this.isSubmitting = false,
    this.isSubmitted = false,
    this.errorMessage,
  });

  JournalEntryFormData copyWith({
    JournalEntry? existingEntry,
    List<JournalEntryLine>? existingLines,
    List<Account>? availableAccounts,
    bool? isSubmitting,
    bool? isSubmitted,
    String? errorMessage,
  }) {
    return JournalEntryFormData(
      existingEntry: existingEntry ?? this.existingEntry,
      existingLines: existingLines ?? this.existingLines,
      availableAccounts: availableAccounts ?? this.availableAccounts,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      isSubmitted: isSubmitted ?? this.isSubmitted,
      errorMessage: errorMessage,
    );
  }
}

/// Bloc for managing journal entry form (create/view)
class JournalEntryFormBloc extends RealtimeBloc<JournalEntryFormData, JournalEntryFormEvent> {
  final JournalRepository _repository;

  JournalEntryFormBloc(this._repository)
      : super(RealtimeSuccess<JournalEntryFormData>(data: const JournalEntryFormData()));

  @override
  Stream<JournalEntryFormData> get dataStream => const Stream.empty();

  @override
  void registerEventHandlers() {
    on<JournalEntryFormLoadRequested>(_onLoadRequested);
    on<JournalEntryFormSubmitRequested>(_onSubmitRequested);
  }

  Future<void> _onLoadRequested(
    JournalEntryFormLoadRequested event,
    Emitter<RealtimeState<JournalEntryFormData>> emit,
  ) async {
    emit(const RealtimeLoading<JournalEntryFormData>());

    try {
      // Always load available accounts for the form
      final accountsStream = _repository.watchAllAccounts();
      final accounts = await accountsStream.first;

      if (event.entryId == null) {
        emit(RealtimeSuccess<JournalEntryFormData>(
          data: JournalEntryFormData(availableAccounts: accounts),
        ));
        return;
      }

      final entry = await _repository.getJournalEntry(event.entryId!);
      if (entry != null) {
        final lines = await _repository.getJournalEntryLines(event.entryId!);
        emit(RealtimeSuccess<JournalEntryFormData>(
          data: JournalEntryFormData(
            existingEntry: entry,
            existingLines: lines,
            availableAccounts: accounts,
          ),
        ));
      } else {
        emit(RealtimeError<JournalEntryFormData>(error: 'Journal entry not found'));
      }
    } catch (e, st) {
      emit(RealtimeError<JournalEntryFormData>(error: e, stackTrace: st));
    }
  }

  Future<void> _onSubmitRequested(
    JournalEntryFormSubmitRequested event,
    Emitter<RealtimeState<JournalEntryFormData>> emit,
  ) async {
    final previousData = currentData;
    emit(RealtimeSuccess<JournalEntryFormData>(
      data: (previousData ?? const JournalEntryFormData()).copyWith(isSubmitting: true),
    ));

    try {
      // Validate balanced entry
      Decimal totalDebits = Decimal.zero;
      Decimal totalCredits = Decimal.zero;
      for (final line in event.lines) {
        totalDebits += line.debitCents;
        totalCredits += line.creditCents;
      }

      if (totalDebits != totalCredits) {
        emit(RealtimeSuccess<JournalEntryFormData>(
          data: (previousData ?? const JournalEntryFormData()).copyWith(
            isSubmitting: false,
            errorMessage: 'Entry is not balanced: debits and credits must be equal',
          ),
        ));
        return;
      }

      if (event.lines.length < 2) {
        emit(RealtimeSuccess<JournalEntryFormData>(
          data: (previousData ?? const JournalEntryFormData()).copyWith(
            isSubmitting: false,
            errorMessage: 'Journal entry must have at least 2 lines',
          ),
        ));
        return;
      }

      await _repository.createJournalEntryWithLines(
        description: event.description,
        entryDate: event.entryDate,
        entryType: 'manual',
        lines: event.lines,
        createdBy: event.createdBy,
      );

      emit(RealtimeSuccess<JournalEntryFormData>(
        data: (previousData ?? const JournalEntryFormData()).copyWith(
          isSubmitting: false,
          isSubmitted: true,
        ),
      ));
    } catch (e) {
      emit(RealtimeSuccess<JournalEntryFormData>(
        data: (previousData ?? const JournalEntryFormData()).copyWith(
          isSubmitting: false,
          errorMessage: e.toString(),
        ),
      ));
    }
  }
}
