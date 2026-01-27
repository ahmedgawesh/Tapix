import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

class ExportProgressWidget extends StatelessWidget {
  final double? progress;

  const ExportProgressWidget({
    super.key,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'export_products.progress'.tr(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (progress != null) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 4),
              Text(
                '${(progress! * 100).toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
