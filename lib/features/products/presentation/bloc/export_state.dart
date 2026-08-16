import 'dart:typed_data';

import 'package:equatable/equatable.dart';

import '../../domain/entities/product_entity.dart';
import 'export_event.dart';

enum ExportOperationStatus { idle, inProgress, success }

class ExportPayload extends Equatable {
  final ExportFormat format;
  final ExportAction action;
  final Uint8List bytes;
  final String filename;

  const ExportPayload({
    required this.format,
    required this.action,
    required this.bytes,
    required this.filename,
  });

  @override
  List<Object?> get props => [format, action, bytes, filename];
}

class ExportUiData extends Equatable {
  final List<Product> products;
  final Set<int> selectedProductIds;
  final ExportFormat format;
  final int? categoryId;
  final int? supplierId;
  final bool activeOnly;
  final ExportOperationStatus operationStatus;
  final double? progress;
  final ExportPayload? lastExport;

  const ExportUiData({
    required this.products,
    required this.selectedProductIds,
    required this.format,
    required this.categoryId,
    required this.supplierId,
    required this.activeOnly,
    required this.operationStatus,
    required this.progress,
    required this.lastExport,
  });

  factory ExportUiData.empty() {
    return const ExportUiData(
      products: <Product>[],
      selectedProductIds: <int>{},
      format: ExportFormat.csv,
      categoryId: null,
      supplierId: null,
      activeOnly: true,
      operationStatus: ExportOperationStatus.idle,
      progress: null,
      lastExport: null,
    );
  }

  ExportUiData copyWith({
    List<Product>? products,
    Set<int>? selectedProductIds,
    ExportFormat? format,
    int? categoryId,
    int? supplierId,
    bool? activeOnly,
    ExportOperationStatus? operationStatus,
    double? progress,
    ExportPayload? lastExport,
    bool clearLastExport = false,
  }) {
    return ExportUiData(
      products: products ?? this.products,
      selectedProductIds: selectedProductIds ?? this.selectedProductIds,
      format: format ?? this.format,
      categoryId: categoryId ?? this.categoryId,
      supplierId: supplierId ?? this.supplierId,
      activeOnly: activeOnly ?? this.activeOnly,
      operationStatus: operationStatus ?? this.operationStatus,
      progress: progress ?? this.progress,
      lastExport: clearLastExport ? null : (lastExport ?? this.lastExport),
    );
  }

  @override
  List<Object?> get props => [
    products,
    selectedProductIds,
    format,
    categoryId,
    supplierId,
    activeOnly,
    operationStatus,
    progress,
    lastExport,
  ];
}
