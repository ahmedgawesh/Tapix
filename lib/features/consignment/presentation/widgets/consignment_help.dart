import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Explains document effects before the operator commits an inventory change.
class ConsignmentHelpCard extends StatelessWidget {
  const ConsignmentHelpCard({super.key, required this.messageKey});

  final String messageKey;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: colors.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: colors.onSecondaryContainer),
            const SizedBox(height: 8),
            Text(
              messageKey.tr(),
              style: TextStyle(color: colors.onSecondaryContainer),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => showConsignmentGuide(context),
              icon: const Icon(Icons.help_outline),
              label: Text('consignment.guide_title'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showConsignmentGuide(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => const ConsignmentGuideDialog(),
);

class ConsignmentGuideDialog extends StatelessWidget {
  const ConsignmentGuideDialog({super.key});

  static const sections = [
    'ownership',
    'agreement',
    'import',
    'receipt',
    'example',
    'mixed',
    'sale',
    'return',
    'custody',
    'settlement',
    'reports',
    'conversion',
    'existing',
  ];

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text('consignment.guide_title'.tr()),
    content: SizedBox(
      width: 600,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final section in sections)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'consignment.guide_${section}_title'.tr(),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('consignment.guide_${section}_body'.tr()),
                ],
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text('common.close'.tr()),
      ),
    ],
  );
}
