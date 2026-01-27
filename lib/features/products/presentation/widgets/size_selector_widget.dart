import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../domain/entities/size_entity.dart';
import '../bloc/sizes_bloc.dart';
import '../bloc/sizes_event.dart';

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
    return BlocProvider(
      create: (context) => sl<SizesBloc>()..add(const LoadSizes()),
      child: BlocBuilder<SizesBloc, RealtimeState<List<Size>>>(
        builder: (context, state) {
          final sizes = state is RealtimeSuccess<List<Size>> 
              ? state.data 
              : <Size>[];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<int>(
                initialValue: selectedSizeId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'product_form_variantSize'.tr(),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(LucideIcons.ruler),
                ),
                items: [
                  DropdownMenuItem<int>(
                    value: null,
                    child: Text('common.none'.tr()),
                  ),
                  ...sizes.map((size) => DropdownMenuItem<int>(
                    value: size.id,
                    child: Text(size.name),
                  )),
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
      ),
    );
  }
}
