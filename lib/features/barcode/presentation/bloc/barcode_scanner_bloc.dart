import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../products/domain/entities/product_entity.dart';
import '../../../products/domain/repositories/product_repository.dart';
import '../../domain/entities/scanner_result.dart';
import '../../services/barcode_validation_service.dart';

// State
class ScannerState extends Equatable {
  final bool isScanning;
  final ScannerResult? lastResult;
  final Product? foundProduct;
  final String? error;
  final bool isSearching;

  const ScannerState({
    this.isScanning = false,
    this.lastResult,
    this.foundProduct,
    this.error,
    this.isSearching = false,
  });

  ScannerState copyWith({
    bool? isScanning,
    ScannerResult? lastResult,
    Product? foundProduct,
    String? error,
    bool? isSearching,
    bool clearResult = false,
    bool clearProduct = false,
    bool clearError = false,
  }) {
    return ScannerState(
      isScanning: isScanning ?? this.isScanning,
      lastResult: clearResult ? null : (lastResult ?? this.lastResult),
      foundProduct: clearProduct ? null : (foundProduct ?? this.foundProduct),
      error: clearError ? null : (error ?? this.error),
      isSearching: isSearching ?? this.isSearching,
    );
  }

  @override
  List<Object?> get props => [
    isScanning,
    lastResult,
    foundProduct,
    error,
    isSearching,
  ];
}

// Events
abstract class BarcodeScannerEvent extends RealtimeEvent {
  const BarcodeScannerEvent();
}

class StartScanning extends BarcodeScannerEvent {
  const StartScanning();
}

class StopScanning extends BarcodeScannerEvent {
  const StopScanning();
}

class BarcodeDetected extends BarcodeScannerEvent {
  final String barcode;
  final BarcodeFormat format;

  const BarcodeDetected({required this.barcode, required this.format});
}

class ManualBarcodeEntered extends BarcodeScannerEvent {
  final String barcode;

  const ManualBarcodeEntered(this.barcode);
}

class ClearScanResult extends BarcodeScannerEvent {
  const ClearScanResult();
}

// Bloc
class BarcodeScannerBloc
    extends RealtimeBloc<ScannerState, BarcodeScannerEvent> {
  final ProductRepository productRepository;
  final BarcodeValidationService validationService;

  BarcodeScannerBloc({
    required this.productRepository,
    required this.validationService,
  }) : super(RealtimeSuccess(data: const ScannerState()));

  @override
  Stream<ScannerState> get dataStream => Stream.value(const ScannerState());

  @override
  void registerEventHandlers() {
    on<StartScanning>(_onStartScanning);
    on<StopScanning>(_onStopScanning);
    on<BarcodeDetected>(_onBarcodeDetected);
    on<ManualBarcodeEntered>(_onManualBarcodeEntered);
    on<ClearScanResult>(_onClearScanResult);
  }

  void _onStartScanning(
    StartScanning event,
    Emitter<RealtimeState<ScannerState>> emit,
  ) {
    final currentState = _getCurrentState();
    emit(
      RealtimeSuccess(
        data: currentState.copyWith(isScanning: true, clearError: true),
      ),
    );
  }

  void _onStopScanning(
    StopScanning event,
    Emitter<RealtimeState<ScannerState>> emit,
  ) {
    final currentState = _getCurrentState();
    emit(RealtimeSuccess(data: currentState.copyWith(isScanning: false)));
  }

  Future<void> _onBarcodeDetected(
    BarcodeDetected event,
    Emitter<RealtimeState<ScannerState>> emit,
  ) async {
    final currentState = _getCurrentState();

    // Validate barcode
    final validation = validationService.validateBarcode(
      event.barcode,
      event.format,
    );
    if (!validation.isValid) {
      emit(
        RealtimeSuccess(
          data: currentState.copyWith(
            error: validation.errorMessage,
            clearProduct: true,
          ),
        ),
      );
      return;
    }

    // Create scan result
    final scanResult = ScannerResult(
      barcode: event.barcode,
      format: event.format,
      timestamp: DateTime.now(),
    );

    emit(
      RealtimeSuccess(
        data: currentState.copyWith(
          lastResult: scanResult,
          isSearching: true,
          clearError: true,
          clearProduct: true,
        ),
      ),
    );

    // Search for product
    try {
      final product = await productRepository.findByBarcode(event.barcode);
      emit(
        RealtimeSuccess(
          data: _getCurrentState().copyWith(
            foundProduct: product,
            isSearching: false,
          ),
        ),
      );
    } catch (e) {
      emit(
        RealtimeSuccess(
          data: _getCurrentState().copyWith(
            error: 'Failed to search for product: $e',
            isSearching: false,
          ),
        ),
      );
    }
  }

  Future<void> _onManualBarcodeEntered(
    ManualBarcodeEntered event,
    Emitter<RealtimeState<ScannerState>> emit,
  ) async {
    final barcode = event.barcode.trim();
    if (barcode.isEmpty) return;

    final format = validationService.detectFormat(barcode);

    // Process barcode directly instead of adding another event
    final validation = validationService.validateBarcode(barcode, format);
    if (!validation.isValid) {
      emit(
        RealtimeSuccess(
          data: _getCurrentState().copyWith(
            error: validation.errorMessage,
            clearProduct: true,
          ),
        ),
      );
      return;
    }

    final scanResult = ScannerResult(
      barcode: barcode,
      format: format,
      timestamp: DateTime.now(),
    );

    emit(
      RealtimeSuccess(
        data: _getCurrentState().copyWith(
          lastResult: scanResult,
          isSearching: true,
          clearError: true,
          clearProduct: true,
        ),
      ),
    );

    try {
      final product = await productRepository.findByBarcode(barcode);
      emit(
        RealtimeSuccess(
          data: _getCurrentState().copyWith(
            foundProduct: product,
            isSearching: false,
          ),
        ),
      );
    } catch (e) {
      emit(
        RealtimeSuccess(
          data: _getCurrentState().copyWith(
            error: 'Failed to search for product: $e',
            isSearching: false,
          ),
        ),
      );
    }
  }

  void _onClearScanResult(
    ClearScanResult event,
    Emitter<RealtimeState<ScannerState>> emit,
  ) {
    final currentState = _getCurrentState();
    emit(
      RealtimeSuccess(
        data: currentState.copyWith(
          clearResult: true,
          clearProduct: true,
          clearError: true,
        ),
      ),
    );
  }

  ScannerState _getCurrentState() {
    final state = this.state;
    if (state is RealtimeSuccess<ScannerState>) {
      return state.data;
    }
    return const ScannerState();
  }
}
