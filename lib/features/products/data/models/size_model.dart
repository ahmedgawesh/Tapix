import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart' as db;
import '../../domain/entities/size_entity.dart';

class SizeModel extends Size {
  const SizeModel({
    required super.id,
    required super.name,
    super.description,
    required super.sortOrder,
    required super.isActive,
  });

  factory SizeModel.fromDrift(db.Size size) {
    return SizeModel(
      id: size.id,
      name: size.name,
      description: size.description,
      sortOrder: size.sortOrder,
      isActive: size.isActive,
    );
  }

  db.SizesCompanion toCompanion() {
    return db.SizesCompanion(
      id: Value(id),
      name: Value(name),
      description: Value(description),
      sortOrder: Value(sortOrder),
      isActive: Value(isActive),
    );
  }
}
