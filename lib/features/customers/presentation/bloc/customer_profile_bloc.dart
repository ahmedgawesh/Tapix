import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/repositories/customer_repository.dart';

abstract class CustomerProfileEvent extends RealtimeEvent {
  const CustomerProfileEvent();
}

class CustomerProfileLoadRequested extends CustomerProfileEvent {
  final int customerId;
  const CustomerProfileLoadRequested(this.customerId);
}

class CustomerProfileBloc extends RealtimeBloc<Customer?, CustomerProfileEvent> {
  final CustomerRepository _repository;
  int? _customerId;

  CustomerProfileBloc(this._repository) : super(const RealtimeLoading());

  @override
  Stream<Customer?> get dataStream {
    final id = _customerId;
    if (id == null) return Stream.value(null);
    return _repository.watchCustomer(id);
  }

  @override
  void registerEventHandlers() {
    on<CustomerProfileLoadRequested>(_onLoadRequested);
  }

  void _onLoadRequested(
    CustomerProfileLoadRequested event,
    Emitter<RealtimeState<Customer?>> emit,
  ) {
    _customerId = event.customerId;
    refresh();
  }
}
