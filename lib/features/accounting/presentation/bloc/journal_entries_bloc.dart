import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/repositories/journal_repository.dart';

/// Events for JournalEntriesBloc
abstract class JournalEntriesEvent extends RealtimeEvent {
  const JournalEntriesEvent();
}

class JournalEntriesInitialized extends JournalEntriesEvent {
  const JournalEntriesInitialized();
}

class JournalEntriesSearchRequested extends JournalEntriesEvent {
  final String query;
  const JournalEntriesSearchRequested(this.query);
}

class JournalEntriesFilterByStatusRequested extends JournalEntriesEvent {
  final String? status;
  const JournalEntriesFilterByStatusRequested(this.status);
}

class JournalEntriesFilterByTypeRequested extends JournalEntriesEvent {
  final String? entryType;
  const JournalEntriesFilterByTypeRequested(this.entryType);
}

class JournalEntriesFilterByDateRangeRequested extends JournalEntriesEvent {
  final DateTime? startDate;
  final DateTime? endDate;
  const JournalEntriesFilterByDateRangeRequested({
    this.startDate,
    this.endDate,
  });
}

class JournalEntryPostRequested extends JournalEntriesEvent {
  final int entryId;
  final int? postedBy;
  const JournalEntryPostRequested(this.entryId, {this.postedBy});
}

class JournalEntryVoidRequested extends JournalEntriesEvent {
  final int entryId;
  final String reason;
  final int? createdBy;
  const JournalEntryVoidRequested(
    this.entryId, {
    required this.reason,
    this.createdBy,
  });
}

/// State data for journal entries list
class JournalEntriesData {
  final List<JournalEntry> entries;
  final String? searchQuery;
  final String? filterStatus;
  final String? filterType;
  final bool isSearching;

  const JournalEntriesData({
    required this.entries,
    this.searchQuery,
    this.filterStatus,
    this.filterType,
    this.isSearching = false,
  });
}

/// Bloc for managing journal entries list with real-time updates
class JournalEntriesBloc
    extends RealtimeBloc<JournalEntriesData, JournalEntriesEvent> {
  final JournalRepository _repository;
  String? _currentSearchQuery;
  String? _currentFilterStatus;
  String? _currentFilterType;
  DateTime? _startDate;
  DateTime? _endDate;

  JournalEntriesBloc(this._repository) : super(const RealtimeLoading());

  @override
  Stream<JournalEntriesData> get dataStream {
    Stream<List<JournalEntry>> stream;

    if (_startDate != null && _endDate != null) {
      stream = _repository.watchJournalEntriesByDateRange(
        _startDate!,
        _endDate!,
      );
    } else if (_currentFilterStatus != null) {
      stream = _repository.watchJournalEntriesByStatus(_currentFilterStatus!);
    } else if (_currentFilterType != null) {
      stream = _repository.watchJournalEntriesByType(_currentFilterType!);
    } else {
      stream = _repository.watchAllJournalEntries();
    }

    return stream.map(
      (entries) => JournalEntriesData(
        entries: entries,
        searchQuery: _currentSearchQuery,
        filterStatus: _currentFilterStatus,
        filterType: _currentFilterType,
        isSearching:
            _currentSearchQuery != null && _currentSearchQuery!.isNotEmpty,
      ),
    );
  }

  @override
  void registerEventHandlers() {
    on<JournalEntriesSearchRequested>(_onSearchRequested);
    on<JournalEntriesFilterByStatusRequested>(_onFilterByStatus);
    on<JournalEntriesFilterByTypeRequested>(_onFilterByType);
    on<JournalEntriesFilterByDateRangeRequested>(_onFilterByDateRange);
    on<JournalEntryPostRequested>(_onPostRequested);
    on<JournalEntryVoidRequested>(_onVoidRequested);
  }

  Future<void> _onSearchRequested(
    JournalEntriesSearchRequested event,
    Emitter<RealtimeState<JournalEntriesData>> emit,
  ) async {
    _currentSearchQuery = event.query.isEmpty ? null : event.query;

    if (event.query.isEmpty) {
      refresh();
      return;
    }

    final previousData = currentData;
    emit(RealtimeLoading<JournalEntriesData>(previousData: previousData));

    try {
      final results = await _repository.searchJournalEntries(event.query);
      emit(
        RealtimeSuccess<JournalEntriesData>(
          data: JournalEntriesData(
            entries: results,
            searchQuery: event.query,
            filterStatus: _currentFilterStatus,
            filterType: _currentFilterType,
            isSearching: true,
          ),
        ),
      );
    } catch (e, st) {
      emit(
        RealtimeError<JournalEntriesData>(
          error: e,
          stackTrace: st,
          previousData: previousData,
        ),
      );
    }
  }

  Future<void> _onFilterByStatus(
    JournalEntriesFilterByStatusRequested event,
    Emitter<RealtimeState<JournalEntriesData>> emit,
  ) async {
    _currentFilterStatus = event.status;
    _currentFilterType = null;
    _startDate = null;
    _endDate = null;
    refresh();
  }

  Future<void> _onFilterByType(
    JournalEntriesFilterByTypeRequested event,
    Emitter<RealtimeState<JournalEntriesData>> emit,
  ) async {
    _currentFilterType = event.entryType;
    _currentFilterStatus = null;
    _startDate = null;
    _endDate = null;
    refresh();
  }

  Future<void> _onFilterByDateRange(
    JournalEntriesFilterByDateRangeRequested event,
    Emitter<RealtimeState<JournalEntriesData>> emit,
  ) async {
    _startDate = event.startDate;
    _endDate = event.endDate;
    _currentFilterStatus = null;
    _currentFilterType = null;
    if (event.startDate == null || event.endDate == null) {
      _startDate = null;
      _endDate = null;
    }
    refresh();
  }

  Future<void> _onPostRequested(
    JournalEntryPostRequested event,
    Emitter<RealtimeState<JournalEntriesData>> emit,
  ) async {
    try {
      await _repository.postJournalEntry(
        event.entryId,
        postedBy: event.postedBy,
      );
    } catch (e, st) {
      emit(
        RealtimeError<JournalEntriesData>(
          error: e,
          stackTrace: st,
          previousData: currentData,
        ),
      );
    }
  }

  Future<void> _onVoidRequested(
    JournalEntryVoidRequested event,
    Emitter<RealtimeState<JournalEntriesData>> emit,
  ) async {
    try {
      await _repository.voidJournalEntry(
        event.entryId,
        reason: event.reason,
        createdBy: event.createdBy,
      );
    } catch (e, st) {
      emit(
        RealtimeError<JournalEntriesData>(
          error: e,
          stackTrace: st,
          previousData: currentData,
        ),
      );
    }
  }
}
