import '../../../../core/bloc/realtime_bloc.dart';
import '../../domain/entities/product_color_entity.dart';

abstract class ColorsEvent extends RealtimeEvent {
  const ColorsEvent();
}

class LoadColors extends ColorsEvent {
  const LoadColors();
}

class SearchColors extends ColorsEvent {
  final String query;

  const SearchColors(this.query);
}

class CreateColor extends ColorsEvent {
  final String name;
  final String? hexCode;

  const CreateColor({
    required this.name,
    this.hexCode,
  });
}

class UpdateColor extends ColorsEvent {
  final ProductColor color;

  const UpdateColor(this.color);
}

class DeleteColor extends ColorsEvent {
  final int colorId;

  const DeleteColor(this.colorId);
}
