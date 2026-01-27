import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:easy_localization/easy_localization.dart';

class ProductSearchWidget extends StatelessWidget {
  final ValueChanged<String> onChanged;
  final VoidCallback? onScanBarcode;
  final VoidCallback? onVoiceSearch;
  final String? initialQuery;

  const ProductSearchWidget({
    super.key,
    required this.onChanged,
    this.onScanBarcode,
    this.onVoiceSearch,
    this.initialQuery,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SearchBar(
        leading: const Icon(LucideIcons.search),
        hintText: 'products_search_hint'.tr(),
        controller: TextEditingController(text: initialQuery),
        onChanged: onChanged,
        trailing: [
          if (onVoiceSearch != null)
            IconButton(
              icon: const Icon(LucideIcons.mic),
              onPressed: onVoiceSearch,
              tooltip: 'products_search_voice'.tr(),
            ),
          if (onScanBarcode != null)
            IconButton(
              icon: const Icon(LucideIcons.scanLine),
              onPressed: onScanBarcode,
              tooltip: 'barcode.scan'.tr(),
            ),
        ],
      ),
    );
  }
}
