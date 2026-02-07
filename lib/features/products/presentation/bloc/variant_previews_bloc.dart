import '../../../../core/bloc/realtime_bloc.dart';
import '../../domain/repositories/product_variant_repository.dart';

class VariantPreview {
  final String? sizeName;
  final String? colorHex;

  const VariantPreview({
    required this.sizeName,
    required this.colorHex,
  });
}

class VariantPreviewsBloc extends RealtimeBloc<Map<int, VariantPreview>, RealtimeEvent> {
  final ProductVariantRepository _repository;

  VariantPreviewsBloc(this._repository) : super(const RealtimeLoading());

  @override
  Stream<Map<int, VariantPreview>> get dataStream {
    return _repository.watchVariantPreviews().map((raw) {
      final mapped = <int, VariantPreview>{};
      raw.forEach((productId, preview) {
        mapped[productId] = VariantPreview(
          sizeName: preview.sizeName,
          colorHex: preview.colorHex,
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
