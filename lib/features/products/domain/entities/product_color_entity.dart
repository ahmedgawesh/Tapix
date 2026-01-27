import 'package:equatable/equatable.dart';

class ProductColor extends Equatable {
  final int id;
  final String name;
  final String? hexCode;
  final bool isActive;

  const ProductColor({
    required this.id,
    required this.name,
    this.hexCode,
    required this.isActive,
  });

  @override
  List<Object?> get props => [id, name, hexCode, isActive];
}
