import '../../../../core/bloc/realtime_bloc.dart';
import '../../domain/repositories/product_variant_repository.dart';

class VariantSummary {
  final int count;
  final int totalStock;

  const VariantSummary({required this.count, required this.totalStock});
}

class VariantSummariesBloc
    extends RealtimeBloc<Map<int, VariantSummary>, RealtimeEvent> {
  final ProductVariantRepository _repository;

  VariantSummariesBloc(this._repository) : super(const RealtimeLoading());

  @override
  Stream<Map<int, VariantSummary>> get dataStream {
    return _repository.watchVariantSummaries().map((raw) {
      final mapped = <int, VariantSummary>{};
      raw.forEach((productId, summary) {
        mapped[productId] = VariantSummary(
          count: summary.count,
          totalStock: summary.totalStock,
        );
      });
      return mapped;
    });
  }

  @override
  void registerEventHandlers() {
    // No custom events.
  }

  @override
  void refresh() => add(const RealtimeRefreshRequested());
}
