import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/database/app_database.dart';

class TemplateSelectorWidget extends StatelessWidget {
  final List<BarcodeTemplate> templates;
  final BarcodeTemplate? selectedTemplate;
  final ValueChanged<BarcodeTemplate> onSelect;

  const TemplateSelectorWidget({
    super.key,
    required this.templates,
    required this.selectedTemplate,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (templates.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'barcode.no_templates'.tr(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.outline,
                ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate card width based on available space
        final availableWidth = constraints.maxWidth;
        final cardWidth = (availableWidth / 4).clamp(100.0, 140.0);
        
        return ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          itemCount: templates.length,
          itemBuilder: (context, index) {
            final template = templates[index];
            final isSelected = selectedTemplate?.id == template.id;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _TemplateCard(
                template: template,
                isSelected: isSelected,
                onTap: () => onSelect(template),
                cardWidth: cardWidth,
              ),
            );
          },
        );
      },
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final BarcodeTemplate template;
  final bool isSelected;
  final VoidCallback onTap;
  final double cardWidth;

  const _TemplateCard({
    required this.template,
    required this.isSelected,
    required this.onTap,
    required this.cardWidth,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: isSelected ? colorScheme.primaryContainer : colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: cardWidth,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? colorScheme.primary : colorScheme.outline.withValues(alpha: 0.3),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _getIconForPaperSize(template.paperSize),
                size: 18,
                color: isSelected ? colorScheme.primary : colorScheme.onSurface,
              ),
              if (template.isDefault) 
                Icon(
                  LucideIcons.star,
                  size: 10,
                  color: colorScheme.tertiary,
                ),
              const SizedBox(height: 2),
              Flexible(
                child: Text(
                  template.name,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
                        fontSize: 9,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                '${template.widthMm.toInt()}x${template.heightMm.toInt()}mm',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: isSelected
                          ? colorScheme.onPrimaryContainer.withValues(alpha: 0.7)
                          : colorScheme.outline,
                      fontSize: 8,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getIconForPaperSize(String paperSize) {
    switch (paperSize.toLowerCase()) {
      case '58mm':
        return LucideIcons.receipt;
      case '80mm':
        return LucideIcons.fileText;
      case 'a4':
        return LucideIcons.file;
      default:
        return LucideIcons.layoutTemplate;
    }
  }
}
