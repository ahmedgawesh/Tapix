import 'package:equatable/equatable.dart';

class Size extends Equatable {
  final int id;
  final String name;
  final String? description;
  final int sortOrder;
  final bool isActive;

  const Size({
    required this.id,
    required this.name,
    this.description,
    required this.sortOrder,
    required this.isActive,
  });

  @override
  List<Object?> get props => [id, name, description, sortOrder, isActive];
}
