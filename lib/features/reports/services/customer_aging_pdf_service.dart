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
import '../presentation/bloc/customer_aging_report_bloc.dart';

class CustomerAgingPdfService {
  static Future<void> printCustomerAgingReport({
    required BuildContext context,
    required CustomerAgingReportData data,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();

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
          'CustomerAgingReport_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> shareCustomerAgingReport({
    required BuildContext context,
    required CustomerAgingReportData data,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();

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
          'CustomerAgingReport_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  static Future<pw.Document> _buildPdf({
    required CustomerAgingReportData data,
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
              _t('customer_aging_report', lang),
              fonts,
              dir,
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              '${_t('as_of', lang)}: ${DateFormat('dd/MM/yyyy').format(data.dateRange.endDate)}',
              style: pw.TextStyle(font: fonts.regular, fontSize: 10),
            ),
            pw.SizedBox(height: 4),
            // Summary row
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '${_t('total_receivables', lang)}: ${cs.formatCents(data.grandTotalCents)}',
                  style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                ),
                pw.Text(
                  '${_t('total_overdue', lang)}: ${cs.formatCents(data.grandTotalOverdueCents)}',
                  style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                ),
                pw.Text(
                  '${_t('total_customers', lang)}: ${data.customerCount}',
                  style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                ),
              ],
            ),
            pw.SizedBox(height: 12),

            // Aging summary
            pw.Text(
              _t('aging_summary', lang),
              style: pw.TextStyle(font: fonts.bold, fontSize: 12),
            ),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 9),
              cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 9),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
              cellAlignments: {
                0: pw.Alignment.centerRight,
                1: pw.Alignment.centerRight,
                2: pw.Alignment.centerRight,
                3: pw.Alignment.centerRight,
                4: pw.Alignment.centerRight,
                5: pw.Alignment.centerRight,
              },
              headers: [
                _t('current', lang),
                _t('days_1_30', lang),
                _t('days_31_60', lang),
                _t('days_61_90', lang),
                _t('over_90', lang),
                _t('total', lang),
              ],
              data: [
                [
                  cs.formatCents(data.grandTotalCurrentCents),
                  cs.formatCents(data.grandTotal30Cents),
                  cs.formatCents(data.grandTotal60Cents),
                  cs.formatCents(data.grandTotal90Cents),
                  cs.formatCents(data.grandTotalOver90Cents),
                  cs.formatCents(data.grandTotalCents),
                ],
              ],
            ),
            pw.SizedBox(height: 12),

            // Customer aging detail table
            if (data.customers.isNotEmpty) ...[
              pw.Text(
                _t('customer_aging_detail', lang),
                style: pw.TextStyle(font: fonts.bold, fontSize: 12),
              ),
              pw.SizedBox(height: 6),
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 8),
                cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 8),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey200,
                ),
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.centerRight,
                  3: pw.Alignment.centerRight,
                  4: pw.Alignment.centerRight,
                  5: pw.Alignment.centerRight,
                  6: pw.Alignment.centerRight,
                  7: pw.Alignment.centerRight,
                },
                headers: [
                  _t('customer', lang),
                  _t('contact', lang),
                  _t('current', lang),
                  _t('days_1_30', lang),
                  _t('days_31_60', lang),
                  _t('days_61_90', lang),
                  _t('over_90', lang),
                  _t('total', lang),
                ],
                data: data.customers.map((item) {
                  return [
                    item.customerName,
                    item.phone ?? item.email ?? '-',
                    item.currentCents > 0
                        ? cs.formatCents(item.currentCents)
                        : '-',
                    item.days30Cents > 0
                        ? cs.formatCents(item.days30Cents)
                        : '-',
                    item.days60Cents > 0
                        ? cs.formatCents(item.days60Cents)
                        : '-',
                    item.days90Cents > 0
                        ? cs.formatCents(item.days90Cents)
                        : '-',
                    item.over90Cents > 0
                        ? cs.formatCents(item.over90Cents)
                        : '-',
                    cs.formatCents(item.totalCents),
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
                      style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                    ),
                    pw.Text(
                      cs.formatCents(data.grandTotalCents),
                      style: pw.TextStyle(font: fonts.bold, fontSize: 11),
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
    'customer_aging_report': {
      'en': 'Customer Aging Report',
      'ar': 'تقرير أعمار ديون العملاء',
      'fr': 'Rapport d\'Ancienneté des Clients',
    },
    'as_of': {'en': 'As of', 'ar': 'حتى تاريخ', 'fr': 'Au'},
    'total_receivables': {
      'en': 'Total Receivables',
      'ar': 'إجمالي المستحقات',
      'fr': 'Total des Créances',
    },
    'total_overdue': {
      'en': 'Total Overdue',
      'ar': 'إجمالي المتأخرات',
      'fr': 'Total en Retard',
    },
    'total_customers': {'en': 'Customers', 'ar': 'العملاء', 'fr': 'Clients'},
    'aging_summary': {
      'en': 'Aging Summary',
      'ar': 'ملخص الأعمار',
      'fr': 'Résumé par Ancienneté',
    },
    'customer_aging_detail': {
      'en': 'Customer Aging Detail',
      'ar': 'تفاصيل أعمار ديون العملاء',
      'fr': 'Détail d\'Ancienneté par Client',
    },
    'customer': {'en': 'Customer', 'ar': 'العميل', 'fr': 'Client'},
    'contact': {'en': 'Contact', 'ar': 'الاتصال', 'fr': 'Contact'},
    'current': {'en': 'Current', 'ar': 'حالي', 'fr': 'Courant'},
    'days_1_30': {'en': '1-30 Days', 'ar': '1-30 يوم', 'fr': '1-30 Jours'},
    'days_31_60': {'en': '31-60 Days', 'ar': '31-60 يوم', 'fr': '31-60 Jours'},
    'days_61_90': {'en': '61-90 Days', 'ar': '61-90 يوم', 'fr': '61-90 Jours'},
    'over_90': {'en': '90+ Days', 'ar': '90+ يوم', 'fr': '90+ Jours'},
    'total': {'en': 'Total', 'ar': 'المجموع', 'fr': 'Total'},
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
