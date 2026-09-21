import '../presentation/widgets/warehouse_report_context.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/di/injection_container.dart';
import '../../../core/services/currency_service.dart';
import '../../settings/data/services/company_profile_service.dart';
import '../../settings/domain/entities/company_profile.dart';
import '../presentation/bloc/salespeople_commission_report_bloc.dart';

class SalespeopleCommissionPdfService {
  static Future<void> printSalespeopleCommissionReport({
    required BuildContext context,
    required SalespeopleCommissionReportData data,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final reportLocation = WarehouseReportContext.maybeOf(context);
    await reportLocation?.scope.checkAccess();
    final loadedCompany = await sl<CompanyProfileService>().getProfile();
    final company =
        reportLocation?.decorateCompany(loadedCompany) ?? loadedCompany;

    final pdf = await _buildPdf(
      data: data,
      cs: cs,
      locale: locale,
      isRtl: isRtl,
      company: company,
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name:
          'SalespeopleCommissionReport_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> shareSalespeopleCommissionReport({
    required BuildContext context,
    required SalespeopleCommissionReportData data,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final reportLocation = WarehouseReportContext.maybeOf(context);
    await reportLocation?.scope.checkAccess();
    final loadedCompany = await sl<CompanyProfileService>().getProfile();
    final company =
        reportLocation?.decorateCompany(loadedCompany) ?? loadedCompany;

    final pdf = await _buildPdf(
      data: data,
      cs: cs,
      locale: locale,
      isRtl: isRtl,
      company: company,
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'SalespeopleCommissionReport_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  static Future<pw.Document> _buildPdf({
    required SalespeopleCommissionReportData data,
    required CurrencyService cs,
    required Locale locale,
    required bool isRtl,
    required CompanyProfile company,
  }) async {
    final fonts = await _loadFonts();
    final pdf = pw.Document();
    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final lang = locale.languageCode;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        textDirection: dir,
        build: (pw.Context context) {
          return [
            _buildHeader(
              company,
              _t('salespeople_commission_report', lang),
              fonts,
              dir,
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              '${_t('period', lang)}: ${DateFormat('dd/MM/yyyy').format(data.dateRange.startDate)} — ${DateFormat('dd/MM/yyyy').format(data.dateRange.endDate)}',
              style: pw.TextStyle(font: fonts.regular, fontSize: 10),
            ),
            pw.SizedBox(height: 4),

            pw.Text(
              _t(
                data.scope == CommissionReportScope.account
                    ? 'scope_account'
                    : 'scope_warehouse',
                lang,
              ),
              style: pw.TextStyle(font: fonts.regular, fontSize: 10),
            ),
            pw.SizedBox(height: 4),

            // Summary row
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '${_t('total_sales', lang)}: ${cs.formatCents(data.grandTotalSalesCents)}',
                  style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                ),
                pw.Text(
                  '${_t('total_commission', lang)}: ${cs.formatCents(data.grandTotalCommissionCents)}',
                  style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                ),
                pw.Text(
                  '${_t('total_paid', lang)}: ${cs.formatCents(data.grandTotalPaidCents)}',
                  style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '${_t('total_salespeople', lang)}: ${data.totalSalespeople}',
                  style: pw.TextStyle(font: fonts.regular, fontSize: 10),
                ),
                pw.Text(
                  '${_t('total_invoices', lang)}: ${data.totalSalesCount}',
                  style: pw.TextStyle(font: fonts.regular, fontSize: 10),
                ),
                pw.Text(
                  '${_t('avg_commission_rate', lang)}: ${data.avgCommissionRatePercent.toStringAsFixed(1)}%',
                  style: pw.TextStyle(font: fonts.regular, fontSize: 10),
                ),
                pw.Text(
                  '${_t('avg_target', lang)}: ${data.avgTargetAchievementPercent.toStringAsFixed(1)}%',
                  style: pw.TextStyle(font: fonts.regular, fontSize: 10),
                ),
              ],
            ),
            pw.SizedBox(height: 12),

            // Salesperson data table
            if (data.salespeople.isNotEmpty) ...[
              pw.Text(
                _t('commission_details', lang),
                style: pw.TextStyle(font: fonts.bold, fontSize: 12),
              ),
              pw.SizedBox(height: 6),
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 7),
                cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 7),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey200,
                ),
                cellAlignments: {
                  0: pw.Alignment.center,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.centerRight,
                  3: pw.Alignment.center,
                  4: pw.Alignment.center,
                  5: pw.Alignment.centerRight,
                  6: pw.Alignment.centerRight,
                  7: pw.Alignment.centerRight,
                  8: pw.Alignment.center,
                },
                headers: [
                  '#',
                  _t('salesperson', lang),
                  _t('sales', lang),
                  _t('invoices', lang),
                  _t('rate', lang),
                  _t('commission', lang),
                  _t('paid', lang),
                  _t('pending', lang),
                  _t('target', lang),
                ],
                data: data.salespeople.asMap().entries.map((entry) {
                  final idx = entry.key + 1;
                  final item = entry.value;
                  return [
                    '$idx',
                    item.employeeName,
                    cs.formatCents(item.totalSalesCents),
                    '${item.salesCount}',
                    '${item.commissionRatePercent.toStringAsFixed(1)}%',
                    cs.formatCents(item.totalCommissionEarnedCents),
                    cs.formatCents(item.paidCommissionCents),
                    cs.formatCents(item.pendingCommissionCents),
                    '${item.targetAchievementPercent.toStringAsFixed(0)}%',
                  ];
                }).toList(),
              ),
              pw.SizedBox(height: 8),
              // Totals footer
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      '${_t('grand_total', lang)}:',
                      style: pw.TextStyle(font: fonts.bold, fontSize: 10),
                    ),
                    pw.Row(
                      children: [
                        pw.Text(
                          '${_t('sales', lang)}: ${cs.formatCents(data.grandTotalSalesCents)}',
                          style: pw.TextStyle(font: fonts.regular, fontSize: 8),
                        ),
                        pw.SizedBox(width: 12),
                        pw.Text(
                          '${_t('commission', lang)}: ${cs.formatCents(data.grandTotalCommissionCents)}',
                          style: pw.TextStyle(font: fonts.regular, fontSize: 8),
                        ),
                        pw.SizedBox(width: 12),
                        pw.Text(
                          '${_t('paid', lang)}: ${cs.formatCents(data.grandTotalPaidCents)}',
                          style: pw.TextStyle(font: fonts.bold, fontSize: 9),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            pw.SizedBox(height: 16),
            pw.Divider(),
            pw.Text(
              '${_t('printed_on', lang)}: ${DateFormat('dd/MM/yyyy').add_jm().format(DateTime.now())}',
              style: pw.TextStyle(
                font: fonts.regular,
                fontSize: 8,
                color: PdfColors.grey600,
              ),
            ),
          ];
        },
      ),
    );

    return pdf;
  }

  // ═══════════════════════════════════════════════════════
  // 3-LANGUAGE TRANSLATIONS FOR PDF
  // ═══════════════════════════════════════════════════════

  static const _translations = {
    'scope_account': {
      'ar': 'الحساب الكامل داخل قاعدة البيانات',
      'en': 'Full account in this database',
      'fr': 'Compte complet dans cette base de données',
    },
    'scope_warehouse': {
      'ar': 'المخزن الرئيسي فقط',
      'en': 'Primary warehouse only',
      'fr': 'Entrepôt principal uniquement',
    },
    'salespeople_commission_report': {
      'en': 'Salespeople Commission Report',
      'ar': 'تقرير عمولات مندوبي المبيعات',
      'fr': 'Rapport de Commissions des Vendeurs',
    },
    'period': {'en': 'Period', 'ar': 'الفترة', 'fr': 'Période'},
    'total_sales': {
      'en': 'Total Sales',
      'ar': 'إجمالي المبيعات',
      'fr': 'Total Ventes',
    },
    'total_commission': {
      'en': 'Total Commission',
      'ar': 'إجمالي العمولات',
      'fr': 'Total Commissions',
    },
    'total_paid': {
      'en': 'Total Paid',
      'ar': 'إجمالي المدفوع',
      'fr': 'Total Payé',
    },
    'total_salespeople': {
      'en': 'Total Salespeople',
      'ar': 'إجمالي المندوبين',
      'fr': 'Total Vendeurs',
    },
    'total_invoices': {
      'en': 'Total Invoices',
      'ar': 'إجمالي الفواتير',
      'fr': 'Total Factures',
    },
    'avg_commission_rate': {
      'en': 'Avg Commission Rate',
      'ar': 'متوسط نسبة العمولة',
      'fr': 'Taux Commission Moyen',
    },
    'avg_target': {
      'en': 'Avg Target Achievement',
      'ar': 'متوسط تحقيق الهدف',
      'fr': 'Réalisation Objectif Moyen',
    },
    'commission_details': {
      'en': 'Commission Details',
      'ar': 'تفاصيل العمولات',
      'fr': 'Détails des Commissions',
    },
    'salesperson': {'en': 'Salesperson', 'ar': 'المندوب', 'fr': 'Vendeur'},
    'sales': {'en': 'Sales', 'ar': 'المبيعات', 'fr': 'Ventes'},
    'invoices': {'en': 'Invoices', 'ar': 'الفواتير', 'fr': 'Factures'},
    'rate': {'en': 'Rate', 'ar': 'النسبة', 'fr': 'Taux'},
    'commission': {'en': 'Commission', 'ar': 'العمولة', 'fr': 'Commission'},
    'paid': {'en': 'Paid', 'ar': 'مدفوع', 'fr': 'Payé'},
    'pending': {'en': 'Pending', 'ar': 'معلق', 'fr': 'En Attente'},
    'target': {'en': 'Target', 'ar': 'الهدف', 'fr': 'Objectif'},
    'grand_total': {
      'en': 'Grand Total',
      'ar': 'المجموع الكلي',
      'fr': 'Total Général',
    },
    'printed_on': {'en': 'Printed on', 'ar': 'طُبع في', 'fr': 'Imprimé le'},
  };

  static String _t(String key, String lang) {
    return _translations[key]?[lang] ?? _translations[key]?['en'] ?? key;
  }

  // ═══════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════

  static pw.Widget _buildHeader(
    CompanyProfile company,
    String title,
    _PdfFonts fonts,
    pw.TextDirection dir,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          company.name,
          style: pw.TextStyle(font: fonts.bold, fontSize: 16),
        ),
        if (company.address != null && company.address!.isNotEmpty)
          pw.Text(
            company.address!,
            style: pw.TextStyle(
              font: fonts.regular,
              fontSize: 9,
              color: PdfColors.grey600,
            ),
          ),
        pw.SizedBox(height: 8),
        pw.Divider(),
        pw.SizedBox(height: 4),
        pw.Center(
          child: pw.Text(
            title,
            style: pw.TextStyle(font: fonts.bold, fontSize: 14),
          ),
        ),
      ],
    );
  }

  static Future<_PdfFonts> _loadFonts() async {
    try {
      final regularData = await rootBundle.load(
        'assets/fonts/IBMPlexSansArabic-Regular.ttf',
      );
      final boldData = await rootBundle.load(
        'assets/fonts/IBMPlexSansArabic-Bold.ttf',
      );
      return _PdfFonts(
        regular: pw.Font.ttf(regularData),
        bold: pw.Font.ttf(boldData),
      );
    } catch (_) {
      return _PdfFonts(
        regular: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
      );
    }
  }
}

class _PdfFonts {
  final pw.Font regular;
  final pw.Font bold;

  _PdfFonts({required this.regular, required this.bold});
}
