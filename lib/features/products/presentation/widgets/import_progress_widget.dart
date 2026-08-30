import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../bloc/import_products_state.dart';

class ImportProgressWidget extends StatelessWidget {
  final ImportInProgress state;
  final bool isDesktop;

  const ImportProgressWidget({
    super.key,
    required this.state,
    required this.isDesktop,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isDesktop ? 600 : double.infinity,
        ),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.loader2, size: 64, color: colorScheme.primary),
                const SizedBox(height: 24),
                Text(
                  'import_products.importing'.tr(),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 32),
                LinearProgressIndicator(value: state.progress, minHeight: 8),
                const SizedBox(height: 16),
                Text(
                  'import_products.progress_status'.tr(
                    args: [
                      state.processedRows.toString(),
                      state.totalRows.toString(),
                      (state.progress * 100).toStringAsFixed(0),
                    ],
                  ),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                Text(
                  'import_products.please_wait'.tr(),
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
