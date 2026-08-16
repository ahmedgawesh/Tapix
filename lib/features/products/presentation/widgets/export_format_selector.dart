import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../bloc/export_bloc.dart';
import '../bloc/export_event.dart';

class ExportFormatSelector extends StatefulWidget {
  const ExportFormatSelector({super.key});

  @override
  State<ExportFormatSelector> createState() => _ExportFormatSelectorState();
}

class _ExportFormatSelectorState extends State<ExportFormatSelector> {
  ExportFormat _selectedFormat = ExportFormat.csv;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _buildFormatCard(
            context,
            format: ExportFormat.csv,
            icon: LucideIcons.fileText,
            title: 'export_products.csv_format'.tr(),
            description: 'export_products.csv_description'.tr(),
            isSelected: _selectedFormat == ExportFormat.csv,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildFormatCard(
            context,
            format: ExportFormat.excel,
            icon: LucideIcons.fileSpreadsheet,
            title: 'export_products.excel_format'.tr(),
            description: 'export_products.excel_description'.tr(),
            isSelected: _selectedFormat == ExportFormat.excel,
          ),
        ),
      ],
    );
  }

  Widget _buildFormatCard(
    BuildContext context, {
    required ExportFormat format,
    required IconData icon,
    required String title,
    required String description,
    required bool isSelected,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedFormat = format;
        });
        context.read<ExportBloc>().add(UpdateExportFormat(format));
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? colorScheme.primary : colorScheme.outline,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: isSelected
              ? colorScheme.primaryContainer.withValues(alpha: 0.1)
              : null,
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: isSelected ? colorScheme.primary : colorScheme.onSurface,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: isSelected ? colorScheme.primary : null,
                fontWeight: isSelected ? FontWeight.bold : null,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
