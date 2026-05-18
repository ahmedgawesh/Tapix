import '../../../../core/bloc/realtime_bloc.dart';
import '../../domain/entities/expiry_summary.dart';
import '../../domain/repositories/product_repository.dart';

/// Streams a per-product [ExpirySummary] map keyed by `productId`, mirroring
/// the existing `VariantSummariesBloc` pattern that drives the same product
/// list screen. Only products tracked as `batch_expiry` with on-hand stock
/// appear in the map; the tile renders a badge or nothing accordingly.
///
/// The bloc is intentionally thin — all SQL lives in `ProductDao` (`watch
/// ExpirySummaries`). The bloc only converts the raw row tuple into the
/// domain [ExpirySummary], computing `daysUntilNearestExpiry` once per
/// emission so the tile never recomputes a date diff during build.
class ExpirySummariesBloc
    extends RealtimeBloc<Map<int, ExpirySummary>, RealtimeEvent> {
  final ProductRepository _repository;

  ExpirySummariesBloc(this._repository) : super(const RealtimeLoading());

  @override
  Stream<Map<int, ExpirySummary>> get dataStream {
    return _repository.watchExpirySummaries().map((raw) {
      final now = DateTime.now();
      // Normalise to start-of-day so the diff is in whole calendar days
      // regardless of when the user opens the screen — matches Odoo's
      // "days_to_expiry" behaviour.
      final startOfToday = DateTime(now.year, now.month, now.day);
      final out = <int, ExpirySummary>{};
      raw.forEach((productId, row) {
        final hasExpired = row.expiredQty > 0;
        final next = row.nextExpiry;
        int? daysUntil;
        if (next != null) {
          final diff = next.difference(startOfToday).inDays;
          // Guard: clamp negatives to 0 (would only happen if `next` slipped
          // past today between the SQL eval and the bloc emission — i.e.
          // midnight rollover in flight).
          daysUntil = diff < 0 ? 0 : diff;
        }
        out[productId] = ExpirySummary(
          hasExpired: hasExpired,
          expiredQuantity: row.expiredQty,
          nearestExpiry: next,
          daysUntilNearestExpiry: daysUntil,
        );
      });
      return out;
    });
  }

  @override
  void registerEventHandlers() {
    // No custom events — the underlying Drift stream is reactive.
  }

  @override
  void refresh() => add(const RealtimeRefreshRequested());
}
