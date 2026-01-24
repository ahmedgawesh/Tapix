import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Base state class for all realtime bloc states
abstract class RealtimeState<T> {
  const RealtimeState();
}

/// Initial state before any data is loaded
class RealtimeInitial<T> extends RealtimeState<T> {
  const RealtimeInitial();
}

/// Loading state while waiting for initial data or refresh
class RealtimeLoading<T> extends RealtimeState<T> {
  final T? previousData;

  const RealtimeLoading({this.previousData});
}

/// Success state with data
class RealtimeSuccess<T> extends RealtimeState<T> {
  final T data;
  final DateTime lastUpdated;

  RealtimeSuccess({required this.data}) : lastUpdated = DateTime.now();
}

/// Error state with optional previous data
class RealtimeError<T> extends RealtimeState<T> {
  final Object error;
  final StackTrace? stackTrace;
  final T? previousData;
  final DateTime timestamp;

  RealtimeError({
    required this.error,
    this.stackTrace,
    this.previousData,
  }) : timestamp = DateTime.now();

  @override
  String toString() => 'RealtimeError(error: $error)';
}

/// Optimistic update state (data changed locally, pending confirmation)
class RealtimeOptimistic<T> extends RealtimeState<T> {
  final T optimisticData;
  final T previousData;
  final String operationId;

  const RealtimeOptimistic({
    required this.optimisticData,
    required this.previousData,
    required this.operationId,
  });
}

/// Base events for realtime bloc
abstract class RealtimeEvent {
  const RealtimeEvent();
}

/// Event triggered when stream emits new data
class RealtimeDataUpdated<T> extends RealtimeEvent {
  final T data;

  const RealtimeDataUpdated(this.data);
}

/// Event triggered when stream encounters an error
class RealtimeErrorOccurred extends RealtimeEvent {
  final Object error;
  final StackTrace? stackTrace;

  const RealtimeErrorOccurred(this.error, [this.stackTrace]);
}

/// Event to trigger refresh/reload
class RealtimeRefreshRequested extends RealtimeEvent {
  const RealtimeRefreshRequested();
}

/// Event for optimistic update
class RealtimeOptimisticUpdate<T> extends RealtimeEvent {
  final T optimisticData;
  final String operationId;

  const RealtimeOptimisticUpdate({
    required this.optimisticData,
    required this.operationId,
  });
}

/// Event to confirm optimistic update succeeded
class RealtimeOptimisticConfirmed extends RealtimeEvent {
  final String operationId;

  const RealtimeOptimisticConfirmed(this.operationId);
}

/// Event to rollback optimistic update
class RealtimeOptimisticRollback extends RealtimeEvent {
  final String operationId;
  final Object? error;

  const RealtimeOptimisticRollback(this.operationId, [this.error]);
}

/// Abstract base class for blocs that react to database streams.
/// 
/// Type parameters:
/// - [T]: The data type emitted by the stream
/// - [E]: Additional event types specific to the implementing bloc
abstract class RealtimeBloc<T, E extends RealtimeEvent>
    extends Bloc<RealtimeEvent, RealtimeState<T>> {
  StreamSubscription<T>? _subscription;
  final Map<String, T> _pendingOptimisticUpdates = {};
  bool _isDisposed = false;

  RealtimeBloc([RealtimeState<T>? initialState])
      : super(initialState ?? const RealtimeLoading()) {
    on<RealtimeDataUpdated<T>>(_onDataUpdated);
    on<RealtimeErrorOccurred>(_onErrorOccurred);
    on<RealtimeRefreshRequested>(_onRefreshRequested);
    on<RealtimeOptimisticUpdate<T>>(_onOptimisticUpdate);
    on<RealtimeOptimisticConfirmed>(_onOptimisticConfirmed);
    on<RealtimeOptimisticRollback>(_onOptimisticRollback);

    registerEventHandlers();

    _initializeStream();
  }

  /// Override this to provide the stream to subscribe to
  Stream<T> get dataStream;

  /// Override this to handle custom events
  void registerEventHandlers();

  /// Override this to customize how incoming stream values map to bloc states.
  @protected
  RealtimeState<T> mapDataToState(T data) => RealtimeSuccess<T>(data: data);

  /// Override this to customize how errors map to bloc states.
  @protected
  RealtimeState<T> mapErrorToState(
    Object error, {
    StackTrace? stackTrace,
    T? previousData,
  }) {
    return RealtimeError<T>(
      error: error,
      stackTrace: stackTrace,
      previousData: previousData,
    );
  }

  void _initializeStream() {
    _subscribe();
  }

  void _subscribe() {
    _subscription?.cancel();
    _subscription = dataStream.listen(
      (data) {
        if (!_isDisposed) {
          add(RealtimeDataUpdated<T>(data));
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_isDisposed) {
          add(RealtimeErrorOccurred(error, stackTrace));
        }
      },
    );
  }

  void _onDataUpdated(
    RealtimeDataUpdated<T> event,
    Emitter<RealtimeState<T>> emit,
  ) {
    if (state is RealtimeOptimistic<T>) {
      return;
    }
    emit(mapDataToState(event.data));
  }

  void _onErrorOccurred(
    RealtimeErrorOccurred event,
    Emitter<RealtimeState<T>> emit,
  ) {
    final previousData = _extractData(state);
    emit(
      mapErrorToState(
        event.error,
        stackTrace: event.stackTrace,
        previousData: previousData,
      ),
    );
  }

  void _onRefreshRequested(
    RealtimeRefreshRequested event,
    Emitter<RealtimeState<T>> emit,
  ) {
    final previousData = _extractData(state);
    emit(RealtimeLoading<T>(previousData: previousData));
    _subscribe();
  }

  void _onOptimisticUpdate(
    RealtimeOptimisticUpdate<T> event,
    Emitter<RealtimeState<T>> emit,
  ) {
    final previousData = _extractData(state);
    if (previousData != null) {
      _pendingOptimisticUpdates[event.operationId] = previousData;
      emit(RealtimeOptimistic<T>(
        optimisticData: event.optimisticData,
        previousData: previousData,
        operationId: event.operationId,
      ));
    }
  }

  void _onOptimisticConfirmed(
    RealtimeOptimisticConfirmed event,
    Emitter<RealtimeState<T>> emit,
  ) {
    _pendingOptimisticUpdates.remove(event.operationId);
    if (state is RealtimeOptimistic<T>) {
      final optimisticState = state as RealtimeOptimistic<T>;
      if (optimisticState.operationId == event.operationId) {
        emit(RealtimeSuccess<T>(data: optimisticState.optimisticData));
      }
    }
  }

  void _onOptimisticRollback(
    RealtimeOptimisticRollback event,
    Emitter<RealtimeState<T>> emit,
  ) {
    final previousData = _pendingOptimisticUpdates.remove(event.operationId);
    if (state is RealtimeOptimistic<T>) {
      final optimisticState = state as RealtimeOptimistic<T>;
      if (optimisticState.operationId == event.operationId) {
        if (event.error != null) {
          emit(RealtimeError<T>(
            error: event.error!,
            previousData: previousData ?? optimisticState.previousData,
          ));
        } else {
          emit(RealtimeSuccess<T>(
            data: previousData ?? optimisticState.previousData,
          ));
        }
      }
    }
  }

  T? _extractData(RealtimeState<T> state) {
    if (state is RealtimeSuccess<T>) {
      return state.data;
    } else if (state is RealtimeLoading<T>) {
      return state.previousData;
    } else if (state is RealtimeError<T>) {
      return state.previousData;
    } else if (state is RealtimeOptimistic<T>) {
      return state.optimisticData;
    }
    return null;
  }

  /// Trigger an optimistic update with automatic rollback on failure
  Future<void> performOptimisticUpdate({
    required String operationId,
    required T optimisticData,
    required Future<void> Function() operation,
  }) async {
    add(RealtimeOptimisticUpdate<T>(
      optimisticData: optimisticData,
      operationId: operationId,
    ));

    try {
      await operation();
      add(RealtimeOptimisticConfirmed(operationId));
    } catch (e) {
      add(RealtimeOptimisticRollback(operationId, e));
      rethrow;
    }
  }

  /// Refresh the stream subscription
  void refresh() {
    add(const RealtimeRefreshRequested());
  }

  /// Check if bloc has data
  bool get hasData => state is RealtimeSuccess<T>;

  /// Get current data or null
  T? get currentData => _extractData(state);

  @override
  Future<void> close() async {
    _isDisposed = true;
    await _subscription?.cancel();
    _subscription = null;
    _pendingOptimisticUpdates.clear();
    return super.close();
  }
}
