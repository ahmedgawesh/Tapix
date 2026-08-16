import '../../../../core/bloc/realtime_bloc.dart';
import '../../domain/entities/category_entity.dart';

class LoadCategories extends RealtimeEvent {
  const LoadCategories();
}

class SearchCategories extends RealtimeEvent {
  final String query;

  const SearchCategories(this.query);
}

class CreateCategory extends RealtimeEvent {
  final String name;
  final String? description;
  final int? parentId;

  const CreateCategory({required this.name, this.description, this.parentId});
}

class UpdateCategory extends RealtimeEvent {
  final Category category;

  const UpdateCategory(this.category);
}

class DeleteCategory extends RealtimeEvent {
  final int categoryId;

  const DeleteCategory(this.categoryId);
}

class LoadSubcategories extends RealtimeEvent {
  final int parentId;

  const LoadSubcategories(this.parentId);
}
