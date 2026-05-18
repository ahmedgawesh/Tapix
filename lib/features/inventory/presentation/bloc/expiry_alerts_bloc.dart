import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/services/inventory/expiry_alert_service.dart';
import '../../domain/entities/expiry_alert_item.dart';

/// Streams the realtime expiry-alert snapshot (items + summary counts).
///
/// Used by:
///   * `ExpiryAlertsSection` (dashboard widget) — only reads `summary` plus
///     the first few items for the preview.
///   * `ExpiryReportScreen` — reads the full `items` list and lets the user
///     filter by bucket.
///
/// The bloc is intentionally thin — all SQL lives inside
/// [ExpiryAlertService]. Keeping the bloc behaviour-free means the
/// dashboard widget and the report screen receive **identical numbers**, by
/// construction, with no risk of two parallel queries drifting.
class ExpiryAlertsBloc
    extends RealtimeBloc<ExpiryAlertSnapshot, RealtimeEvent> {
  final ExpiryAlertService _service;

  ExpiryAlertsBloc(this._service) : super(const RealtimeLoading());

  @override
  Stream<ExpiryAlertSnapshot> get dataStream => _service.watchAlerts();

  @override
  void registerEventHandlers() {
    // No custom events — Drift's reactive stream already drives emissions.
  }

  @override
  void refresh() => add(const RealtimeRefreshRequested());
}
