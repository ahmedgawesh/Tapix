import 'package:decimal/decimal.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../domain/entities/product_variant_entity.dart';
import '../../domain/repositories/product_variant_repository.dart';

// Events
abstract class ProductVariantsEvent extends RealtimeEvent {
  const ProductVariantsEvent();
}

class ProductVariantsInitialized extends ProductVariantsEvent {
  final int productId;

  const ProductVariantsInitialized(this.productId);
}

class AllVariantsInitialized extends ProductVariantsEvent {
  const AllVariantsInitialized();
}

class VariantCreateRequested extends ProductVariantsEvent {
  final int productId;
  final String? sku;
  final String? barcode;
  final int? colorId;
  final int? sizeId;
  final Decimal costCents;
  final Decimal priceCents;
  final Decimal? wholesalePriceCents;
  final int stockQuantity;

  const VariantCreateRequested({
    required this.productId,
    this.sku,
    this.barcode,
    this.colorId,
    this.sizeId,
    required this.costCents,
    required this.priceCents,
    this.wholesalePriceCents,
    required this.stockQuantity,
  });
}

class VariantUpdateRequested extends ProductVariantsEvent {
  final ProductVariant variant;

  const VariantUpdateRequested(this.variant);
}

class VariantDeleteRequested extends ProductVariantsEvent {
  final int variantId;

  const VariantDeleteRequested(this.variantId);
}

/// Stock-aware delete: posts a balanced Shrinkage adjustment for the full
/// on-hand quantity (Dr 5800 / Cr 1200) BEFORE running smart delete, so the
/// 1200 Inventory ledger never strays from Σ(stock × cost). Used when the
/// user confirms deletion of a variant that still carries stock.
class VariantWriteOffAndDeleteRequested extends ProductVariantsEvent {
  final int variantId;
  final String reason;

  const VariantWriteOffAndDeleteRequested({
    required this.variantId,
    required this.reason,
  });
}

// Bloc
class ProductVariantsBloc
    extends RealtimeBloc<List<ProductVariant>, ProductVariantsEvent> {
  final ProductVariantRepository _repository;
  int? _productId;
  bool _initialized = false;
  final _uuid = const Uuid();

  ProductVariantsBloc(this._repository) : super(const RealtimeLoading());

  @override
  void registerEventHandlers() {
    on<ProductVariantsInitialized>(_onInitialized);
    on<AllVariantsInitialized>(_onAllInitialized);
    on<VariantCreateRequested>(_onVariantCreate);
    on<VariantUpdateRequested>(_onVariantUpdate);
    on<VariantDeleteRequested>(_onVariantDelete);
    on<VariantWriteOffAndDeleteRequested>(_onVariantWriteOffAndDelete);
  }

  @override
  Stream<List<ProductVariant>> get dataStream {
    // Return empty stream until initialized to avoid watching wrong data
    if (!_initialized) {
      return const Stream.empty();
    }
    if (_productId == null) {
      return _repository.watchAllVariants();
    }
    return _repository.watchVariantsByProduct(_productId!);
  }

  void _onInitialized(
    ProductVariantsInitialized event,
    Emitter<RealtimeState<List<ProductVariant>>> emit,
  ) {
    _productId = event.productId;
    _initialized = true;
    refresh();
  }

  void _onAllInitialized(
    AllVariantsInitialized event,
    Emitter<RealtimeState<List<ProductVariant>>> emit,
  ) {
    _productId = null;
    _initialized = true;
    refresh();
  }

  Future<void> _onVariantCreate(
    VariantCreateRequested event,
    Emitter<RealtimeState<List<ProductVariant>>> emit,
  ) async {
    try {
      await _repository.createVariant(
        productId: event.productId,
        sku: event.sku,
        barcode: event.barcode,
        colorId: event.colorId,
        sizeId: event.sizeId,
        costCents: event.costCents,
        priceCents: event.priceCents,
        wholesalePriceCents: event.wholesalePriceCents,
        stockQuantity: event.stockQuantity,
      );
    } catch (e, st) {
      final msg = e.toString();
      if (msg.contains('no column named price_adjustment_cents') ||
          msg.contains('no column named cost_cents') ||
          msg.contains('no column named price_cents')) {
        add(
          RealtimeErrorOccurred(
            'Database schema is out of date (missing product_variants pricing columns). Please restart the app completely to apply the schema fix.',
            st,
          ),
        );
        return;
      }
      add(RealtimeErrorOccurred(e, st));
    }
  }

  Future<void> _onVariantUpdate(
    VariantUpdateRequested event,
    Emitter<RealtimeState<List<ProductVariant>>> emit,
  ) async {
    final currentData = this.currentData;
    if (currentData == null) {
      try {
        await _repository.updateVariant(event.variant);
      } catch (e, st) {
        add(RealtimeErrorOccurred(e, st));
      }
      return;
    }

    final optimisticData = currentData.map((v) {
      return v.id == event.variant.id ? event.variant : v;
    }).toList();

    try {
      await performOptimisticUpdate(
        operationId: _uuid.v4(),
        optimisticData: optimisticData,
        operation: () => _repository.updateVariant(event.variant),
      );
    } catch (e, st) {
      add(RealtimeErrorOccurred(e, st));
    }
  }

  Future<void> _onVariantDelete(
    VariantDeleteRequested event,
    Emitter<RealtimeState<List<ProductVariant>>> emit,
  ) async {
    final currentData = this.currentData;
    // Smart delete: hard-delete if no references, otherwise deactivate.
    // Mirrors QuickBooks/Xero/Odoo so historical sale/purchase items, return
    // adjustments, inventory adjustments, batches and price-history rows
    // never get orphaned (preserves audit trail + journal integrity).
    if (currentData == null) {
      try {
        await _repository.smartDeleteVariant(event.variantId);
      } catch (e, st) {
        add(RealtimeErrorOccurred(e, st));
      }
      return;
    }

    // Optimistic UX: removing the row from the visible list works for both
    // hard delete and soft delete, because soft-deleted variants drop out of
    // `watchVariantsByProduct` (filtered by is_active).
    final optimisticData = currentData
        .where((v) => v.id != event.variantId)
        .toList();

    try {
      await performOptimisticUpdate(
        operationId: _uuid.v4(),
        optimisticData: optimisticData,
        operation: () => _repository.smartDeleteVariant(event.variantId),
      );
    } catch (e, st) {
      add(RealtimeErrorOccurred(e, st));
    }
  }

  Future<void> _onVariantWriteOffAndDelete(
    VariantWriteOffAndDeleteRequested event,
    Emitter<RealtimeState<List<ProductVariant>>> emit,
  ) async {
    final currentData = this.currentData;
    if (currentData == null) {
      try {
        await _repository.writeOffAndDeleteVariant(
          variantId: event.variantId,
          reason: event.reason,
        );
      } catch (e, st) {
        add(RealtimeErrorOccurred(e, st));
      }
      return;
    }

    final optimisticData = currentData
        .where((v) => v.id != event.variantId)
        .toList();

    try {
      await performOptimisticUpdate(
        operationId: _uuid.v4(),
        optimisticData: optimisticData,
        operation: () => _repository.writeOffAndDeleteVariant(
          variantId: event.variantId,
          reason: event.reason,
        ),
      );
    } catch (e, st) {
      add(RealtimeErrorOccurred(e, st));
    }
  }
}
