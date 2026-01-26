import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../bloc/import_products_bloc.dart';
import '../bloc/import_products_event.dart';
import '../bloc/import_products_state.dart';

class ImportPreviewWidget extends StatelessWidget {
  final ImportValidated state;
  final bool isDesktop;
  final bool isTablet;

  const ImportPreviewWidget({
    super.key,
    required this.state,
    required this.isDesktop,
    required this.isTablet,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasErrors = state.hasErrors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: hasErrors ? colorScheme.errorContainer : colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  hasErrors ? LucideIcons.alertTriangle : LucideIcons.checkCircle,
                  color: hasErrors ? colorScheme.error : colorScheme.primary,
                  size: 32,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasErrors
                            ? 'import_products.validation_failed'.tr()
                            : 'import_products.validation_passed'.tr(),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        hasErrors
                            ? 'import_products.fix_errors_hint'.tr(
                                args: [state.validationErrors.length.toString()],
                              )
                            : 'import_products.ready_to_import'.tr(
                                args: [state.fileData.totalRows.toString()],
                              ),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (hasErrors) ...[
          const SizedBox(height: 24),
          Text(
            'import_products.validation_errors'.tr(),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          Card(
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: state.validationErrors.length > 50 ? 50 : state.validationErrors.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final error = state.validationErrors[index];
                return ListTile(
                  leading: Icon(
                    LucideIcons.alertCircle,
                    color: colorScheme.error,
                  ),
                  title: Text('Row ${error.rowIndex + 2}: ${error.field}'),
                  subtitle: Text(error.message),
                );
              },
            ),
          ),
          if (state.validationErrors.length > 50)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'import_products.showing_first_errors'.tr(args: ['50', state.validationErrors.length.toString()]),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton(
              onPressed: () {
                context.read<ImportProductsBloc>().add(const ImportReset());
              },
              child: Text('import_products.cancel'.tr()),
            ),
            const SizedBox(width: 16),
            FilledButton.icon(
              onPressed: hasErrors
                  ? null
                  : () {
                      context.read<ImportProductsBloc>().add(const ImportExecutionStarted());
                    },
              icon: const Icon(LucideIcons.upload),
              label: Text('import_products.start_import'.tr()),
            ),
          ],
        ),
      ],
    );
  }
}
