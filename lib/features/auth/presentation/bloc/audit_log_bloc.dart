import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/services/audit_log_service.dart';

class AuditLogViewModel extends Equatable {
  final List<AuditLog> logs;
  final List<AuditLog> filteredLogs;
  final String? entityTypeFilter;
  final String? actionFilter;
  final String searchQuery;
  final Map<int, String> userNames;

  const AuditLogViewModel({
    this.logs = const [],
    this.filteredLogs = const [],
    this.entityTypeFilter,
    this.actionFilter,
    this.searchQuery = '',
    this.userNames = const {},
  });

  AuditLogViewModel copyWith({
    List<AuditLog>? logs,
    List<AuditLog>? filteredLogs,
    String? entityTypeFilter,
    String? actionFilter,
    String? searchQuery,
    Map<int, String>? userNames,
  }) {
    return AuditLogViewModel(
      logs: logs ?? this.logs,
      filteredLogs: filteredLogs ?? this.filteredLogs,
      entityTypeFilter: entityTypeFilter ?? this.entityTypeFilter,
      actionFilter: actionFilter ?? this.actionFilter,
      searchQuery: searchQuery ?? this.searchQuery,
      userNames: userNames ?? this.userNames,
    );
  }

  @override
  List<Object?> get props => [
        logs,
        filteredLogs,
        entityTypeFilter,
        actionFilter,
        searchQuery,
        userNames,
      ];
}

// ==================== EVENTS ====================

abstract class AuditLogEvent extends RealtimeEvent {
  const AuditLogEvent();
}

class AuditLogEntityTypeFilterChanged extends AuditLogEvent {
  final String? entityType;
  const AuditLogEntityTypeFilterChanged(this.entityType);
}

class AuditLogActionFilterChanged extends AuditLogEvent {
  final String? action;
  const AuditLogActionFilterChanged(this.action);
}

class AuditLogSearchChanged extends AuditLogEvent {
  final String query;
  const AuditLogSearchChanged(this.query);
}

class AuditLogFiltersCleared extends AuditLogEvent {
  const AuditLogFiltersCleared();
}

class AuditLogUserNamesLoaded extends AuditLogEvent {
  final Map<int, String> userNames;
  const AuditLogUserNamesLoaded(this.userNames);
}

// ==================== BLOC ====================

class AuditLogBloc extends RealtimeBloc<AuditLogViewModel, AuditLogEvent> {
  final AuditLogService _auditService;
  final AppDatabase _db;

  List<AuditLog> _latestLogs = const [];
  String? _entityTypeFilter;
  String? _actionFilter;
  String _searchQuery = '';
  Map<int, String> _userNames = const {};

  AuditLogBloc({
    required AuditLogService auditService,
    required AppDatabase db,
  })  : _auditService = auditService,
        _db = db,
        super(const RealtimeLoading()) {
    _loadUserNames().then(add);
  }

  @override
  Stream<AuditLogViewModel> get dataStream => _auditService
      .watchAuditLogs()
      .map((logs) => _buildViewModel(logs: logs));

  @override
  void registerEventHandlers() {
    on<AuditLogEntityTypeFilterChanged>(_onEntityTypeFilterChanged);
    on<AuditLogActionFilterChanged>(_onActionFilterChanged);
    on<AuditLogSearchChanged>(_onSearchChanged);
    on<AuditLogFiltersCleared>(_onFiltersCleared);
    on<AuditLogUserNamesLoaded>(_onUserNamesLoaded);
  }

  @override
  RealtimeState<AuditLogViewModel> mapDataToState(AuditLogViewModel data) {
    _latestLogs = data.logs;
    return RealtimeSuccess<AuditLogViewModel>(data: data);
  }

  void _onEntityTypeFilterChanged(
    AuditLogEntityTypeFilterChanged event,
    Emitter<RealtimeState<AuditLogViewModel>> emit,
  ) {
    _entityTypeFilter = event.entityType == _entityTypeFilter ? null : event.entityType;
    emit(RealtimeSuccess<AuditLogViewModel>(data: _buildViewModel(logs: _latestLogs)));
  }

  void _onActionFilterChanged(
    AuditLogActionFilterChanged event,
    Emitter<RealtimeState<AuditLogViewModel>> emit,
  ) {
    _actionFilter = event.action == _actionFilter ? null : event.action;
    emit(RealtimeSuccess<AuditLogViewModel>(data: _buildViewModel(logs: _latestLogs)));
  }

  void _onSearchChanged(
    AuditLogSearchChanged event,
    Emitter<RealtimeState<AuditLogViewModel>> emit,
  ) {
    _searchQuery = event.query;
    emit(RealtimeSuccess<AuditLogViewModel>(data: _buildViewModel(logs: _latestLogs)));
  }

  void _onFiltersCleared(
    AuditLogFiltersCleared event,
    Emitter<RealtimeState<AuditLogViewModel>> emit,
  ) {
    _entityTypeFilter = null;
    _actionFilter = null;
    _searchQuery = '';
    emit(RealtimeSuccess<AuditLogViewModel>(data: _buildViewModel(logs: _latestLogs)));
  }

  void _onUserNamesLoaded(
    AuditLogUserNamesLoaded event,
    Emitter<RealtimeState<AuditLogViewModel>> emit,
  ) {
    _userNames = event.userNames;

    final currentData = currentDataOrNull;
    if (currentData == null) return;

    emit(RealtimeSuccess<AuditLogViewModel>(data: _buildViewModel(logs: currentData.logs)));
  }

  AuditLogViewModel _buildViewModel({required List<AuditLog> logs}) {
    final filtered = _applyFilters(
      logs,
      _entityTypeFilter,
      _actionFilter,
      _searchQuery,
      _userNames,
    );

    return AuditLogViewModel(
      logs: logs,
      filteredLogs: filtered,
      entityTypeFilter: _entityTypeFilter,
      actionFilter: _actionFilter,
      searchQuery: _searchQuery,
      userNames: _userNames,
    );
  }

  List<AuditLog> _applyFilters(
    List<AuditLog> logs,
    String? entityType,
    String? action,
    String searchQuery,
    Map<int, String> userNames,
  ) {
    var result = logs;

    if (entityType != null && entityType.isNotEmpty) {
      result = result.where((l) => l.targetTable == entityType).toList();
    }
    if (action != null && action.isNotEmpty) {
      result = result.where((l) => l.action == action).toList();
    }
    if (searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      result = result.where((l) {
        final performedBy = l.changes['performedBy']?.toString().toLowerCase() ?? '';
        return l.targetTable.toLowerCase().contains(q) ||
            l.action.toLowerCase().contains(q) ||
            l.recordId.toString().contains(q) ||
            (userNames[l.userId]?.toLowerCase().contains(q) ?? false) ||
            performedBy.contains(q);
      }).toList();
    }

    return result;
  }

  Future<AuditLogUserNamesLoaded> _loadUserNames() async {
    try {
      final users = await _db.select(_db.users).get();
      return AuditLogUserNamesLoaded({for (final u in users) u.id: u.username});
    } catch (_) {
      return const AuditLogUserNamesLoaded({});
    }
  }

  AuditLogViewModel? get currentDataOrNull {
    final s = state;
    if (s is RealtimeSuccess<AuditLogViewModel>) return s.data;
    if (s is RealtimeLoading<AuditLogViewModel>) return s.previousData;
    if (s is RealtimeError<AuditLogViewModel>) return s.previousData;
    if (s is RealtimeOptimistic<AuditLogViewModel>) return s.optimisticData;
    return null;
  }
}
