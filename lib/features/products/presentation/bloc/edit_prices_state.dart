import 'package:equatable/equatable.dart';
import '../../domain/entities/product_entity.dart';

class EditPricesStateData extends Equatable {
  final List<Product> products;
  final int? categoryId;
  final int? supplierId;
  final String? stockStatus;
  final String? searchQuery;
  final bool hasUnsavedChanges;
  final int displayLimit; // For performance - limit displayed products
  final Set<int> selectedProductIds; // For bulk operations

  const EditPricesStateData({
    this.products = const [],
    this.categoryId,
    this.supplierId,
    this.stockStatus,
    this.searchQuery,
    this.hasUnsavedChanges = false,
    this.displayLimit = 100, // Show 100 products at a time by default
    this.selectedProductIds = const {},
  });

  EditPricesStateData copyWith({
    List<Product>? products,
    int? categoryId,
    int? supplierId,
    String? stockStatus,
    String? searchQuery,
    bool? hasUnsavedChanges,
    int? displayLimit,
    Set<int>? selectedProductIds,
  }) {
    return EditPricesStateData(
      products: products ?? this.products,
      categoryId: categoryId ?? this.categoryId,
      supplierId: supplierId ?? this.supplierId,
      stockStatus: stockStatus ?? this.stockStatus,
      searchQuery: searchQuery ?? this.searchQuery,
      hasUnsavedChanges: hasUnsavedChanges ?? this.hasUnsavedChanges,
      displayLimit: displayLimit ?? this.displayLimit,
      selectedProductIds: selectedProductIds ?? this.selectedProductIds,
    );
  }

  @override
  List<Object?> get props => [
        products,
        categoryId,
        supplierId,
        stockStatus,
        searchQuery,
        hasUnsavedChanges,
        displayLimit,
        selectedProductIds,
      ];
}
