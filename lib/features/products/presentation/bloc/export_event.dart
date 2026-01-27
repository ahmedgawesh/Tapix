import 'package:equatable/equatable.dart';
import '../../../../core/bloc/realtime_bloc.dart';

enum ExportFormat { csv, excel }
enum ExportAction { save, share }

abstract class ExportEvent extends RealtimeEvent with EquatableMixin {
  const ExportEvent();

  @override
  List<Object?> get props => [];
}

class LoadExportPreview extends ExportEvent {
  final int? categoryId;
  final int? supplierId;
  final bool? activeOnly;

  const LoadExportPreview({
    this.categoryId,
    this.supplierId,
    this.activeOnly,
  });

  @override
  List<Object?> get props => [categoryId, supplierId, activeOnly];
}

class ExportToCSV extends ExportEvent {
  final int? categoryId;
  final int? supplierId;
  final bool? activeOnly;
  final ExportAction action;
  final Set<int>? selectedProductIds;

  const ExportToCSV({
    this.categoryId,
    this.supplierId,
    this.activeOnly,
    this.action = ExportAction.save,
    this.selectedProductIds,
  });

  @override
  List<Object?> get props => [categoryId, supplierId, activeOnly, action, selectedProductIds];
}

class ExportToExcel extends ExportEvent {
  final int? categoryId;
  final int? supplierId;
  final bool? activeOnly;
  final ExportAction action;
  final Set<int>? selectedProductIds;

  const ExportToExcel({
    this.categoryId,
    this.supplierId,
    this.activeOnly,
    this.action = ExportAction.save,
    this.selectedProductIds,
  });

  @override
  List<Object?> get props => [categoryId, supplierId, activeOnly, action, selectedProductIds];
}

class UpdateExportFormat extends ExportEvent {
  final ExportFormat format;

  const UpdateExportFormat(this.format);

  @override
  List<Object?> get props => [format];
}

class UpdateCategoryFilter extends ExportEvent {
  final int? categoryId;

  const UpdateCategoryFilter(this.categoryId);

  @override
  List<Object?> get props => [categoryId];
}

class UpdateSupplierFilter extends ExportEvent {
  final int? supplierId;

  const UpdateSupplierFilter(this.supplierId);

  @override
  List<Object?> get props => [supplierId];
}

class UpdateActiveFilter extends ExportEvent {
  final bool? activeOnly;

  const UpdateActiveFilter(this.activeOnly);

  @override
  List<Object?> get props => [activeOnly];
}

class ExportAcknowledged extends ExportEvent {
  const ExportAcknowledged();
}

class ToggleProductSelection extends ExportEvent {
  final int productId;

  const ToggleProductSelection(this.productId);

  @override
  List<Object?> get props => [productId];
}

class ToggleSelectAllProducts extends ExportEvent {
  const ToggleSelectAllProducts();
}
