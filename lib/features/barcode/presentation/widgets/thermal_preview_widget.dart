import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../products/domain/entities/product_entity.dart';
import '../../../settings/domain/entities/company_profile.dart';
import '../../domain/models/barcode_design_state.dart';
import 'barcode_preview_widget.dart';

/// Preview of the continuous label stock produced by a thermal barcode
/// printer. Unlike the A4 preview, every card here represents one physical
/// label at the selected millimetre dimensions.
class ThermalBatchPreviewWidget extends StatelessWidget {
  final List<({Product product, String? variantInfo})> labels;
  final BarcodeDesignSettings settings;
  final CompanyProfile companyProfile;
  final double scale;

  const ThermalBatchPreviewWidget({
    super.key,
    required this.labels,
    required this.settings,
    required this.companyProfile,
    this.scale = 1,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final previewLabels = labels.take(3).toList(growable: false);
    final remaining = labels.length - previewLabels.length;
    final labelWidth = settings.labelWidthMm * 3.78 * scale;
    final rollWidth = labelWidth + 28;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: rollWidth,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: colorScheme.inverseSurface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.print_outlined,
                size: 18,
                color: colorScheme.onInverseSurface,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'barcode.thermal_preview'.tr(),
                  style: TextStyle(
                    color: colorScheme.onInverseSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: rollWidth,
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            border: Border(
              left: BorderSide(color: Colors.grey.shade400),
              right: BorderSide(color: Colors.grey.shade400),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < previewLabels.length; index++) ...[
                BarcodePreviewWidget(
                  product: previewLabels[index].product,
                  settings: settings,
                  companyProfile: companyProfile,
                  variantInfo: previewLabels[index].variantInfo,
                  scale: scale,
                ),
                if (index < previewLabels.length - 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        const Icon(Icons.content_cut, size: 14),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Divider(
                            height: 1,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
        Container(
          width: rollWidth,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(12),
            ),
          ),
          child: Text(
            '${settings.labelWidthMm.toStringAsFixed(0)} × '
            '${settings.labelHeightMm.toStringAsFixed(0)} mm',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        if (remaining > 0) ...[
          const SizedBox(height: 8),
          Text(
            'barcode.more_labels'.tr(args: [remaining.toString()]),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
