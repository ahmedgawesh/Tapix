import 'package:equatable/equatable.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../domain/entities/size_entity.dart';

abstract class SizesEvent extends RealtimeEvent with EquatableMixin {
  const SizesEvent();

  @override
  List<Object?> get props => [];
}

class LoadSizes extends SizesEvent {
  const LoadSizes();
}

class SearchSizes extends SizesEvent {
  final String query;

  const SearchSizes(this.query);

  @override
  List<Object?> get props => [query];
}

class CreateSize extends SizesEvent {
  final String name;
  final String? description;
  final int sortOrder;

  const CreateSize({
    required this.name,
    this.description,
    required this.sortOrder,
  });

  @override
  List<Object?> get props => [name, description, sortOrder];
}

class UpdateSize extends SizesEvent {
  final Size size;

  const UpdateSize(this.size);

  @override
  List<Object?> get props => [size];
}

class DeleteSize extends SizesEvent {
  final int sizeId;

  const DeleteSize(this.sizeId);

  @override
  List<Object?> get props => [sizeId];
}
