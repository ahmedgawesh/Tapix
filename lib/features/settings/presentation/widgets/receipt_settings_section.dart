import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../domain/entities/app_settings.dart';
import '../bloc/app_settings_bloc.dart';
import 'settings_widgets.dart';

class ReceiptSettingsSection extends StatelessWidget {
  const ReceiptSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppSettingsBloc, AppSettingsState>(
      builder: (context, state) {
        final s = state.settings;
        return SettingsExpansionCard(
          title: 'app_settings.receipt.title'.tr(),
          icon: LucideIcons.receipt,
          children: [
            SettingsTextField(
              label: 'app_settings.receipt.header_text'.tr(),
              value: s.receiptHeaderText,
              hint: 'app_settings.receipt.header_hint'.tr(),
              onChanged: (v) => _patch(context, (c) => c.copyWith(receiptHeaderText: v)),
            ),
            SettingsTextField(
              label: 'app_settings.receipt.footer_text'.tr(),
              value: s.receiptFooterText,
              hint: 'app_settings.receipt.footer_hint'.tr(),
              onChanged: (v) => _patch(context, (c) => c.copyWith(receiptFooterText: v)),
            ),
            SwitchListTile(
              title: Text('app_settings.receipt.show_logo'.tr()),
              subtitle: Text('app_settings.receipt.show_logo_desc'.tr()),
              value: s.showLogoOnReceipt,
              onChanged: (v) => _patch(context, (c) => c.copyWith(showLogoOnReceipt: v)),
            ),
            SettingsOptionTile<String>(
              title: 'app_settings.receipt.paper_size'.tr(),
              value: s.receiptPaperSize,
              options: const {'58mm': '58mm', '80mm': '80mm'},
              onChanged: (v) => _patch(context, (c) => c.copyWith(receiptPaperSize: v)),
            ),
            SettingsSliderTile(
              title: 'app_settings.receipt.copies'.tr(),
              value: s.receiptCopies.toDouble(),
              min: 1,
              max: 5,
              divisions: 4,
              onChanged: (v) => _patch(context, (c) => c.copyWith(receiptCopies: v.round())),
            ),
            SwitchListTile(
              title: Text('app_settings.receipt.auto_print'.tr()),
              subtitle: Text('app_settings.receipt.auto_print_desc'.tr()),
              value: s.autoPrintReceipt,
              onChanged: (v) => _patch(context, (c) => c.copyWith(autoPrintReceipt: v)),
            ),
            SwitchListTile(
              title: Text('app_settings.receipt.tax_breakdown'.tr()),
              subtitle: Text('app_settings.receipt.tax_breakdown_desc'.tr()),
              value: s.includeTaxBreakdown,
              onChanged: (v) => _patch(context, (c) => c.copyWith(includeTaxBreakdown: v)),
            ),
            SwitchListTile(
              title: Text('app_settings.receipt.show_on_purchases'.tr()),
              subtitle: Text('app_settings.receipt.show_on_purchases_desc'.tr()),
              value: s.showHeaderFooterOnPurchases,
              onChanged: (v) => _patch(context, (c) => c.copyWith(showHeaderFooterOnPurchases: v)),
            ),
            SettingsOptionTile<String>(
              title: 'app_settings.receipt.language'.tr(),
              value: s.receiptLanguage,
              options: {
                'app': 'app_settings.receipt.lang_app'.tr(),
                'en': 'common.english'.tr(),
                'ar': 'common.arabic'.tr(),
                'fr': 'common.french'.tr(),
              },
              onChanged: (v) => _patch(context, (c) => c.copyWith(receiptLanguage: v)),
            ),
          ],
        );
      },
    );
  }

  void _patch(BuildContext context, AppSettings Function(AppSettings) fn) {
    context.read<AppSettingsBloc>().add(AppSettingsPatched(fn));
  }
}
