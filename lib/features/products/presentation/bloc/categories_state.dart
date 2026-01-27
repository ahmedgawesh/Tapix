import 'package:equatable/equatable.dart';
import '../../domain/entities/category_entity.dart';

abstract class CategoriesState extends Equatable {
  const CategoriesState();

  @override
  List<Object?> get props => [];
}

class CategoriesInitial extends CategoriesState {
  const CategoriesInitial();
}

class CategoriesLoading extends CategoriesState {
  const CategoriesLoading();
}

class CategoriesLoaded extends CategoriesState {
  final List<Category> categories;
  final Map<int, int> productCounts;

  const CategoriesLoaded({
    required this.categories,
    this.productCounts = const {},
  });

  @override
  List<Object?> get props => [categories, productCounts];
}

class CategoriesError extends CategoriesState {
  final String message;

  const CategoriesError(this.message);

  @override
  List<Object?> get props => [message];
}

class CategoryOperationSuccess extends CategoriesState {
  final String message;

  const CategoryOperationSuccess(this.message);

  @override
  List<Object?> get props => [message];
}

class CategoryOperationFailure extends CategoriesState {
  final String message;

  const CategoryOperationFailure(this.message);

  @override
  List<Object?> get props => [message];
}
