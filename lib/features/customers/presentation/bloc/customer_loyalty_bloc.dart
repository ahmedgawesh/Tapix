import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../domain/repositories/loyalty_repository.dart';

/// Events for CustomerLoyaltyBloc
abstract class CustomerLoyaltyEvent extends RealtimeEvent {
  const CustomerLoyaltyEvent();
}

class CustomerLoyaltyLoadRequested extends CustomerLoyaltyEvent {
  final int customerId;
  const CustomerLoyaltyLoadRequested(this.customerId);
}

class CustomerLoyaltyAddPointsRequested extends CustomerLoyaltyEvent {
  final int customerId;
  final int points;
  final String source;
  final String? description;

  const CustomerLoyaltyAddPointsRequested({
    required this.customerId,
    required this.points,
    required this.source,
    this.description,
  });
}

class CustomerLoyaltyRedeemRewardRequested extends CustomerLoyaltyEvent {
  final int customerId;
  final int rewardId;

  const CustomerLoyaltyRedeemRewardRequested({
    required this.customerId,
    required this.rewardId,
  });
}

/// Bloc for customer loyalty management
class CustomerLoyaltyBloc extends RealtimeBloc<CustomerLoyaltySummary?, CustomerLoyaltyEvent> {
  final LoyaltyRepository _repository;
  int? _currentCustomerId;

  CustomerLoyaltyBloc(this._repository) : super(const RealtimeLoading());

  @override
  Stream<CustomerLoyaltySummary?> get dataStream {
    if (_currentCustomerId == null) {
      return Stream.value(null);
    }
    return _repository.watchCustomerLoyaltySummary(_currentCustomerId!);
  }

  @override
  void registerEventHandlers() {
    on<CustomerLoyaltyLoadRequested>(_onLoadRequested);
    on<CustomerLoyaltyAddPointsRequested>(_onAddPointsRequested);
    on<CustomerLoyaltyRedeemRewardRequested>(_onRedeemRewardRequested);
  }

  void _onLoadRequested(
    CustomerLoyaltyLoadRequested event,
    Emitter<RealtimeState<CustomerLoyaltySummary?>> emit,
  ) {
    _currentCustomerId = event.customerId;
    refresh();
  }

  Future<void> _onAddPointsRequested(
    CustomerLoyaltyAddPointsRequested event,
    Emitter<RealtimeState<CustomerLoyaltySummary?>> emit,
  ) async {
    try {
      await _repository.addPoints(
        customerId: event.customerId,
        points: event.points,
        source: event.source,
        description: event.description,
      );
    } catch (e, st) {
      emit(RealtimeError(error: e, stackTrace: st, previousData: currentData));
    }
  }

  Future<void> _onRedeemRewardRequested(
    CustomerLoyaltyRedeemRewardRequested event,
    Emitter<RealtimeState<CustomerLoyaltySummary?>> emit,
  ) async {
    try {
      await _repository.redeemReward(
        customerId: event.customerId,
        rewardId: event.rewardId,
      );
    } catch (e, st) {
      emit(RealtimeError(error: e, stackTrace: st, previousData: currentData));
    }
  }
}
