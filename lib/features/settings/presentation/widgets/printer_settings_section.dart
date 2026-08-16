import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../domain/entities/app_settings.dart';
import '../bloc/app_settings_bloc.dart';
import 'settings_widgets.dart';

class PrinterSettingsSection extends StatelessWidget {
  const PrinterSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppSettingsBloc, AppSettingsState>(
      builder: (context, state) {
        final s = state.settings;
        return SettingsExpansionCard(
          title: 'app_settings.printer.title'.tr(),
          icon: LucideIcons.printer,
          children: [
            SettingsTextField(
              label: 'app_settings.printer.receipt_printer'.tr(),
              value: s.receiptPrinterName,
              hint: 'app_settings.printer.receipt_printer_hint'.tr(),
              onChanged: (v) =>
                  _patch(context, (c) => c.copyWith(receiptPrinterName: v)),
            ),
            const SizedBox(height: 8),
            SettingsTextField(
              label: 'app_settings.printer.label_printer'.tr(),
              value: s.labelPrinterName,
              hint: 'app_settings.printer.label_printer_hint'.tr(),
              onChanged: (v) =>
                  _patch(context, (c) => c.copyWith(labelPrinterName: v)),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('app_settings.printer.test_sent'.tr()),
                    ),
                  );
                },
                icon: const Icon(LucideIcons.printer),
                label: Text('app_settings.printer.test_print'.tr()),
              ),
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  void _patch(BuildContext context, AppSettings Function(AppSettings) fn) {
    context.read<AppSettingsBloc>().add(AppSettingsPatched(fn));
  }
}
