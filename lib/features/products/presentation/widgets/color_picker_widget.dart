import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../domain/entities/product_color_entity.dart';
import '../bloc/colors_bloc.dart';

class ColorPickerWidget extends StatelessWidget {
  final int? selectedColorId;
  final ValueChanged<int?> onColorSelected;

  const ColorPickerWidget({
    super.key,
    this.selectedColorId,
    required this.onColorSelected,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ColorsBloc, RealtimeState<List<ProductColor>>>(
      builder: (context, state) {
        final colors = state is RealtimeSuccess<List<ProductColor>> 
            ? state.data 
            : <ProductColor>[];
            
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<int>(
              initialValue: selectedColorId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'product_form_variantColor'.tr(),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(LucideIcons.palette),
              ),
              items: [
                DropdownMenuItem<int>(
                  value: null,
                  child: Text('common.none'.tr()),
                ),
                ...colors.map((color) {
                  final colorValue = color.hexCode != null 
                      ? Color(int.parse(color.hexCode!.replaceFirst('#', '0xFF'))) 
                      : Colors.grey;
                      
                  return DropdownMenuItem<int>(
                    value: color.id,
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: colorValue,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(color.name),
                        ),
                      ],
                    ),
                  );
                }),
              ],
              onChanged: onColorSelected,
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _showManageColorsDialog(context),
              icon: const Icon(LucideIcons.plus),
              label: Text('manage_colors'.tr()),
            ),
          ],
        );
      },
    );
  }

  void _showManageColorsDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => const _ManageColorsDialog(),
    );
  }
}

class _ManageColorsDialog extends StatefulWidget {
  const _ManageColorsDialog();

  @override
  State<_ManageColorsDialog> createState() => _ManageColorsDialogState();
}

class _ManageColorsDialogState extends State<_ManageColorsDialog> {
  // TODO: Implement color management dialog logic (add/edit/delete colors)
  // For now, just a placeholder to satisfy the requirement
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('manage_colors'.tr()),
      content: Text('color_management_pending'.tr()),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('common.close'.tr()),
        ),
      ],
    );
  }
}
