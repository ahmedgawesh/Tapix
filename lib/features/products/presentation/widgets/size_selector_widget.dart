import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../domain/entities/size_entity.dart';
import '../bloc/sizes_bloc.dart';

class SizeSelectorWidget extends StatelessWidget {
  final int? selectedSizeId;
  final ValueChanged<int?> onSizeSelected;

  const SizeSelectorWidget({
    super.key,
    this.selectedSizeId,
    required this.onSizeSelected,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SizesBloc, RealtimeState<List<Size>>>(
      builder: (context, state) {
        final sizes = state is RealtimeSuccess<List<Size>>
            ? state.data
            : <Size>[];

        final byId = <int, Size>{};
        for (final s in sizes) {
          byId.putIfAbsent(s.id, () => s);
        }
        final uniqueSizes = byId.values.toList();
        uniqueSizes.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );

        final effectiveSelected = selectedSizeId == null
            ? null
            : (byId.containsKey(selectedSizeId!) ? selectedSizeId : null);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<int?>(
              initialValue: effectiveSelected,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'product_form_variantSize'.tr(),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(LucideIcons.ruler),
              ),
              items: [
                DropdownMenuItem<int?>(
                  value: null,
                  child: Text('common.none'.tr()),
                ),
                ...uniqueSizes.map(
                  (size) => DropdownMenuItem<int?>(
                    value: size.id,
                    child: Text(size.name),
                  ),
                ),
              ],
              onChanged: onSizeSelected,
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => context.push('/products/sizes'),
              icon: const Icon(LucideIcons.settings),
              label: Text('manage_sizes'.tr()),
            ),
          ],
        );
      },
    );
  }
}
