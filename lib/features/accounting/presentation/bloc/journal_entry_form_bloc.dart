import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/repositories/journal_repository.dart';

/// Events for JournalEntryFormBloc (read-only — no manual entry creation)
abstract class JournalEntryFormEvent extends RealtimeEvent {
  const JournalEntryFormEvent();
}

class JournalEntryFormLoadRequested extends JournalEntryFormEvent {
  final int? entryId;
  const JournalEntryFormLoadRequested({this.entryId});
}

/// State data for journal entry detail viewer
class JournalEntryFormData {
  final JournalEntry? existingEntry;
  final List<JournalEntryLine> existingLines;
  final List<Account> availableAccounts;

  const JournalEntryFormData({
    this.existingEntry,
    this.existingLines = const [],
    this.availableAccounts = const [],
  });
}

/// Bloc for viewing journal entry details (read-only — no manual creation)
class JournalEntryFormBloc
    extends RealtimeBloc<JournalEntryFormData, JournalEntryFormEvent> {
  final JournalRepository _repository;

  JournalEntryFormBloc(this._repository)
    : super(
        RealtimeSuccess<JournalEntryFormData>(
          data: const JournalEntryFormData(),
        ),
      );

  @override
  Stream<JournalEntryFormData> get dataStream => const Stream.empty();

  @override
  void registerEventHandlers() {
    on<JournalEntryFormLoadRequested>(_onLoadRequested);
  }

  Future<void> _onLoadRequested(
    JournalEntryFormLoadRequested event,
    Emitter<RealtimeState<JournalEntryFormData>> emit,
  ) async {
    emit(const RealtimeLoading<JournalEntryFormData>());

    try {
      final accountsStream = _repository.watchAllAccounts();
      final accounts = await accountsStream.first;

      if (event.entryId == null) {
        emit(
          RealtimeSuccess<JournalEntryFormData>(
            data: JournalEntryFormData(availableAccounts: accounts),
          ),
        );
        return;
      }

      final entry = await _repository.getJournalEntry(event.entryId!);
      if (entry != null) {
        final lines = await _repository.getJournalEntryLines(event.entryId!);
        emit(
          RealtimeSuccess<JournalEntryFormData>(
            data: JournalEntryFormData(
              existingEntry: entry,
              existingLines: lines,
              availableAccounts: accounts,
            ),
          ),
        );
      } else {
        emit(
          RealtimeError<JournalEntryFormData>(error: 'Journal entry not found'),
        );
      }
    } catch (e, st) {
      emit(RealtimeError<JournalEntryFormData>(error: e, stackTrace: st));
    }
  }
}
