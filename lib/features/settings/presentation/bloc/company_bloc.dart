import '../../../../core/bloc/realtime_bloc.dart';
import '../../data/services/company_profile_service.dart';
import '../../domain/entities/company_profile.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class CompanyBloc extends RealtimeBloc<CompanyProfile, CompanyEvent> {
  final CompanyProfileService _service;

  CompanyBloc(this._service) : super(const RealtimeLoading());

  @override
  Stream<CompanyProfile> get dataStream => _service.watchProfile();

  @override
  void registerEventHandlers() {
    on<LoadProfile>(_onLoadProfile);
    on<ProfileUpdated>(_onProfileUpdated);
  }

  Future<void> _onLoadProfile(
    LoadProfile event,
    Emitter<RealtimeState<CompanyProfile>> emit,
  ) async {
    add(const RealtimeRefreshRequested());
  }

  Future<void> _onProfileUpdated(
    ProfileUpdated event,
    Emitter<RealtimeState<CompanyProfile>> emit,
  ) async {
    emit(RealtimeSuccess(data: event.profile));
  }
}

abstract class CompanyEvent extends RealtimeEvent {
  const CompanyEvent();
}

class LoadProfile extends CompanyEvent {
  const LoadProfile();
}

class ProfileUpdated extends CompanyEvent {
  final CompanyProfile profile;
  const ProfileUpdated(this.profile);
}
