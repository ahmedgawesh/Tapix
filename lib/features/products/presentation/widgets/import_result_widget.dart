import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../domain/entities/import_result.dart';
import '../bloc/import_products_bloc.dart';
import '../bloc/import_products_event.dart';

class ImportResultWidget extends StatelessWidget {
  final ImportResult result;
  final bool isDesktop;

  const ImportResultWidget({
    super.key,
    required this.result,
    required this.isDesktop,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSuccess = result.isFullSuccess;
    final isPartial = result.isPartialSuccess;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isDesktop ? 700 : double.infinity,
        ),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  isSuccess
                      ? LucideIcons.checkCircle2
                      : (isPartial
                            ? LucideIcons.alertTriangle
                            : LucideIcons.xCircle),
                  size: 64,
                  color: isSuccess
                      ? Colors.green
                      : (isPartial ? Colors.orange : colorScheme.error),
                ),
                const SizedBox(height: 24),
                Text(
                  isSuccess
                      ? 'import_products.import_success'.tr()
                      : (isPartial
                            ? 'import_products.import_partial'.tr()
                            : 'import_products.import_failed'.tr()),
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                _buildStatRow(
                  context,
                  'import_products.total_rows'.tr(),
                  result.totalRows.toString(),
                  Icons.list,
                ),
                const Divider(height: 24),
                _buildStatRow(
                  context,
                  'import_products.successful_rows'.tr(),
                  result.successfulRows.toString(),
                  LucideIcons.checkCircle,
                  color: Colors.green,
                ),
                const Divider(height: 24),
                _buildStatRow(
                  context,
                  'import_products.failed_rows'.tr(),
                  result.failedRows.toString(),
                  LucideIcons.xCircle,
                  color: result.failedRows > 0 ? colorScheme.error : null,
                ),
                const Divider(height: 24),
                _buildStatRow(
                  context,
                  'import_products.duration'.tr(),
                  _formatDuration(result.duration),
                  LucideIcons.clock,
                ),
                if (result.hasErrors) ...[
                  const SizedBox(height: 32),
                  Text(
                    'import_products.error_summary'.tr(),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    decoration: BoxDecoration(
                      border: Border.all(color: colorScheme.outline),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: result.errors.length > 20
                          ? 20
                          : result.errors.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final error = result.errors[index];
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            LucideIcons.alertCircle,
                            size: 16,
                            color: colorScheme.error,
                          ),
                          title: Text(
                            'Row ${error.rowIndex + 2}: ${error.field}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          subtitle: Text(
                            error.message,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        );
                      },
                    ),
                  ),
                  if (result.errors.length > 20)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'import_products.showing_first_errors'.tr(
                          args: ['20', result.errors.length.toString()],
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
                const SizedBox(height: 32),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 16,
                  runSpacing: 12,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        context.read<ImportProductsBloc>().add(
                          const ImportReset(),
                        );
                      },
                      icon: const Icon(LucideIcons.upload),
                      label: Text('import_products.import_another'.tr()),
                    ),
                    FilledButton.icon(
                      onPressed: () {
                        context.go('/products');
                      },
                      icon: const Icon(LucideIcons.list),
                      label: Text('import_products.view_products'.tr()),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatRow(
    BuildContext context,
    String label,
    String value,
    IconData icon, {
    Color? color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
    } else {
      return '${duration.inSeconds}s';
    }
  }
}
