import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/repositories/supplier_repository.dart';

/// Events for SupplierProfileBloc
abstract class SupplierProfileEvent extends RealtimeEvent {
  const SupplierProfileEvent();
}

class SupplierProfileLoadRequested extends SupplierProfileEvent {
  final int supplierId;
  const SupplierProfileLoadRequested(this.supplierId);
}

/// Bloc for managing a single supplier profile with real-time updates
class SupplierProfileBloc
    extends RealtimeBloc<Supplier?, SupplierProfileEvent> {
  final SupplierRepository _repository;
  int? _supplierId;

  SupplierProfileBloc(this._repository) : super(const RealtimeLoading());

  @override
  Stream<Supplier?> get dataStream {
    if (_supplierId == null) return const Stream.empty();
    return _repository.watchSupplier(_supplierId!);
  }

  @override
  void registerEventHandlers() {
    on<SupplierProfileLoadRequested>(_onLoadRequested);
  }

  void _onLoadRequested(
    SupplierProfileLoadRequested event,
    Emitter<RealtimeState<Supplier?>> emit,
  ) {
    _supplierId = event.supplierId;
    refresh();
  }
}
