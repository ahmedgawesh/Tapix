import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart' as db;
import '../../domain/entities/product_color_entity.dart';

class ProductColorModel extends ProductColor {
  const ProductColorModel({
    required super.id,
    required super.name,
    super.hexCode,
    required super.isActive,
  });

  factory ProductColorModel.fromDrift(db.ProductColor color) {
    return ProductColorModel(
      id: color.id,
      name: color.name,
      hexCode: color.hexCode,
      isActive: color.isActive,
    );
  }

  db.ProductColorsCompanion toCompanion() {
    return db.ProductColorsCompanion(
      id: id > 0 ? Value(id) : const Value.absent(),
      name: Value(name),
      hexCode: Value(hexCode),
      isActive: Value(isActive),
    );
  }
}
