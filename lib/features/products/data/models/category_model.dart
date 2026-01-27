import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart' as db;
import '../../domain/entities/category_entity.dart';

class CategoryModel extends Category {
  const CategoryModel({
    required super.id,
    required super.name,
    super.description,
    super.parentId,
    required super.isActive,
    required super.createdAt,
    required super.updatedAt,
  });

  factory CategoryModel.fromDrift(db.ProductCategory category) {
    return CategoryModel(
      id: category.id,
      name: category.name,
      description: category.description,
      parentId: category.parentId,
      isActive: category.isActive,
      createdAt: category.createdAt,
      updatedAt: category.updatedAt,
    );
  }

  db.ProductCategoriesCompanion toCompanion() {
    return db.ProductCategoriesCompanion(
      id: Value(id),
      name: Value(name),
      description: Value(description),
      parentId: Value(parentId),
      isActive: Value(isActive),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  db.ProductCategoriesCompanion toInsertCompanion() {
    return db.ProductCategoriesCompanion.insert(
      name: name,
      description: Value(description),
      parentId: Value(parentId),
      isActive: Value(isActive),
    );
  }
}
