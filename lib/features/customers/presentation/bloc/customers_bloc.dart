import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/repositories/customer_repository.dart';

/// Events for CustomersBloc
abstract class CustomersEvent extends RealtimeEvent {
  const CustomersEvent();
}

class CustomersLoadRequested extends CustomersEvent {
  const CustomersLoadRequested();
}

class CustomersSearchRequested extends CustomersEvent {
  final String query;
  const CustomersSearchRequested(this.query);
}

class CustomerDeleteRequested extends CustomersEvent {
  final int customerId;
  const CustomerDeleteRequested(this.customerId);
}

class CustomerToggleActiveRequested extends CustomersEvent {
  final Customer customer;
  const CustomerToggleActiveRequested(this.customer);
}

/// State data for customers list
class CustomersData {
  final List<Customer> customers;
  final String? searchQuery;
  final bool isSearching;

  const CustomersData({
    required this.customers,
    this.searchQuery,
    this.isSearching = false,
  });

  CustomersData copyWith({
    List<Customer>? customers,
    String? searchQuery,
    bool? isSearching,
  }) {
    return CustomersData(
      customers: customers ?? this.customers,
      searchQuery: searchQuery ?? this.searchQuery,
      isSearching: isSearching ?? this.isSearching,
    );
  }
}

/// Bloc for managing customers list
class CustomersBloc extends RealtimeBloc<CustomersData, CustomersEvent> {
  final CustomerRepository _repository;
  String? _currentSearchQuery;

  CustomersBloc(this._repository) : super(const RealtimeLoading());

  @override
  Stream<CustomersData> get dataStream {
    return _repository
        .watchAllCustomers(isActive: true)
        .map(
          (customers) => CustomersData(
            customers: customers,
            searchQuery: _currentSearchQuery,
            isSearching:
                _currentSearchQuery != null && _currentSearchQuery!.isNotEmpty,
          ),
        );
  }

  @override
  void registerEventHandlers() {
    on<CustomersSearchRequested>(_onSearchRequested);
    on<CustomerDeleteRequested>(_onDeleteRequested);
    on<CustomerToggleActiveRequested>(_onToggleActiveRequested);
  }

  Future<void> _onSearchRequested(
    CustomersSearchRequested event,
    Emitter<RealtimeState<CustomersData>> emit,
  ) async {
    _currentSearchQuery = event.query.isEmpty ? null : event.query;

    if (event.query.isEmpty) {
      // Reset to watching all customers
      refresh();
      return;
    }

    final previousData = currentData;
    emit(RealtimeLoading<CustomersData>(previousData: previousData));

    try {
      final results = await _repository.searchCustomers(
        event.query,
        isActive: true,
      );
      emit(
        RealtimeSuccess<CustomersData>(
          data: CustomersData(
            customers: results,
            searchQuery: event.query,
            isSearching: true,
          ),
        ),
      );
    } catch (e, st) {
      emit(
        RealtimeError<CustomersData>(
          error: e,
          stackTrace: st,
          previousData: previousData,
        ),
      );
    }
  }

  Future<void> _onDeleteRequested(
    CustomerDeleteRequested event,
    Emitter<RealtimeState<CustomersData>> emit,
  ) async {
    try {
      await _repository.deleteCustomer(event.customerId);
    } catch (e, st) {
      emit(
        RealtimeError<CustomersData>(
          error: e,
          stackTrace: st,
          previousData: currentData,
        ),
      );
    }
  }

  Future<void> _onToggleActiveRequested(
    CustomerToggleActiveRequested event,
    Emitter<RealtimeState<CustomersData>> emit,
  ) async {
    try {
      final updatedCustomer = event.customer.copyWith(
        isActive: !event.customer.isActive,
        updatedAt: DateTime.now(),
      );
      await _repository.updateCustomer(updatedCustomer);
    } catch (e, st) {
      emit(
        RealtimeError<CustomersData>(
          error: e,
          stackTrace: st,
          previousData: currentData,
        ),
      );
    }
  }
}

/// Bloc for customer metrics (counts, totals)
class CustomerMetricsBloc extends RealtimeBloc<CustomerMetrics, RealtimeEvent> {
  final CustomerRepository _repository;

  CustomerMetricsBloc(this._repository) : super(const RealtimeLoading());

  @override
  Stream<CustomerMetrics> get dataStream {
    return _repository.watchCustomerCount(isActive: true).asyncMap((
      count,
    ) async {
      // We need to combine multiple streams, so we'll use a simpler approach
      return CustomerMetrics(
        activeCount: count,
        totalBalanceCents: 0,
        withCreditCount: 0,
        segmentCounts: const {},
      );
    });
  }

  @override
  void registerEventHandlers() {}
}

class CustomerMetrics {
  final int activeCount;
  final int totalBalanceCents;
  final int withCreditCount;
  final Map<String, int> segmentCounts;

  const CustomerMetrics({
    required this.activeCount,
    required this.totalBalanceCents,
    required this.withCreditCount,
    required this.segmentCounts,
  });
}
