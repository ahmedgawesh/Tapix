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
import '../presentation/bloc/customer_analysis_report_bloc.dart';

class CustomerAnalysisPdfService {
  static Future<void> printCustomerAnalysisReport({
    required BuildContext context,
    required CustomerAnalysisReportData data,
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
          'CustomerAnalysisReport_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> shareCustomerAnalysisReport({
    required BuildContext context,
    required CustomerAnalysisReportData data,
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
          'CustomerAnalysisReport_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  static Future<pw.Document> _buildPdf({
    required CustomerAnalysisReportData data,
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
        pageFormat: PdfPageFormat.a4,
        textDirection: dir,
        build: (pw.Context context) {
          return [
            _buildHeader(
              company,
              _t('customer_analysis_report', lang),
              fonts,
              dir,
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              '${_t('period', lang)}: ${DateFormat('dd/MM/yyyy').format(data.dateRange.startDate)} — ${DateFormat('dd/MM/yyyy').format(data.dateRange.endDate)}',
              style: pw.TextStyle(font: fonts.regular, fontSize: 10),
            ),
            pw.SizedBox(height: 4),
            // Summary row
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '${_t('total_spent', lang)}: ${cs.formatCents(data.grandTotalSpentCents)}',
                  style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                ),
                pw.Text(
                  '${_t('total_customers', lang)}: ${data.totalCustomers}',
                  style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '${_t('total_purchases', lang)}: ${data.grandTotalPurchases}',
                  style: pw.TextStyle(font: fonts.regular, fontSize: 10),
                ),
                pw.Text(
                  '${_t('avg_order', lang)}: ${cs.formatCents(data.overallAvgOrderCents)}',
                  style: pw.TextStyle(font: fonts.regular, fontSize: 10),
                ),
              ],
            ),
            pw.SizedBox(height: 12),

            // RFM Segment Summary
            if (data.segmentCounts.isNotEmpty) ...[
              pw.Text(
                _t('rfm_segment_overview', lang),
                style: pw.TextStyle(font: fonts.bold, fontSize: 12),
              ),
              pw.SizedBox(height: 6),
              pw.Wrap(
                spacing: 8,
                runSpacing: 4,
                children: data.segmentCounts.entries.map((e) {
                  return pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey400),
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Text(
                      '${_rfmLabelPdf(e.key, lang)}: ${e.value}',
                      style: pw.TextStyle(font: fonts.regular, fontSize: 8),
                    ),
                  );
                }).toList(),
              ),
              pw.SizedBox(height: 12),
            ],

            // Customer analysis data table
            if (data.customers.isNotEmpty) ...[
              pw.Text(
                _t('customer_analysis_details', lang),
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
                  2: pw.Alignment.centerLeft,
                  3: pw.Alignment.centerRight,
                  4: pw.Alignment.centerRight,
                  5: pw.Alignment.centerRight,
                  6: pw.Alignment.centerRight,
                  7: pw.Alignment.center,
                  8: pw.Alignment.centerLeft,
                },
                headers: [
                  '#',
                  _t('customer', lang),
                  _t('segment', lang),
                  _t('total_spent', lang),
                  _t('purchases', lang),
                  _t('avg_order', lang),
                  _t('avg_frequency', lang),
                  'R/F/M',
                  _t('rfm_segment', lang),
                ],
                data: data.customers.asMap().entries.map((entry) {
                  final idx = entry.key + 1;
                  final item = entry.value;
                  return [
                    '$idx',
                    item.customerName,
                    _segmentLabelPdf(item.segment, lang),
                    cs.formatCents(item.totalSpentCents),
                    '${item.purchaseCount}',
                    cs.formatCents(item.avgOrderValueCents),
                    item.avgDaysBetweenPurchases > 0
                        ? '${item.avgDaysBetweenPurchases.round()} ${_t('days', lang)}'
                        : '-',
                    '${item.recencyScore}/${item.frequencyScore}/${item.monetaryScore}',
                    _rfmLabelPdf(item.rfmSegment, lang),
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
                      cs.formatCents(data.grandTotalSpentCents),
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
    'customer_analysis_report': {
      'en': 'Customer Analysis Report',
      'ar': 'تقرير تحليل العملاء',
      'fr': 'Rapport d\'Analyse des Clients',
    },
    'period': {'en': 'Period', 'ar': 'الفترة', 'fr': 'Période'},
    'total_spent': {
      'en': 'Total Spent',
      'ar': 'إجمالي الإنفاق',
      'fr': 'Total Dépensé',
    },
    'total_customers': {
      'en': 'Total Customers',
      'ar': 'إجمالي العملاء',
      'fr': 'Total Clients',
    },
    'total_purchases': {
      'en': 'Total Purchases',
      'ar': 'إجمالي المشتريات',
      'fr': 'Total Achats',
    },
    'avg_order': {
      'en': 'Avg Order',
      'ar': 'متوسط الطلب',
      'fr': 'Commande Moy.',
    },
    'customer_analysis_details': {
      'en': 'Customer Analysis Details',
      'ar': 'تفاصيل تحليل العملاء',
      'fr': 'Détails de l\'Analyse des Clients',
    },
    'customer': {'en': 'Customer', 'ar': 'العميل', 'fr': 'Client'},
    'segment': {'en': 'Segment', 'ar': 'الفئة', 'fr': 'Segment'},
    'purchases': {'en': 'Purchases', 'ar': 'المشتريات', 'fr': 'Achats'},
    'avg_frequency': {
      'en': 'Avg Freq.',
      'ar': 'متوسط التكرار',
      'fr': 'Fréq. Moy.',
    },
    'rfm_segment': {'en': 'RFM Segment', 'ar': 'فئة RFM', 'fr': 'Segment RFM'},
    'rfm_segment_overview': {
      'en': 'RFM Segment Overview',
      'ar': 'نظرة عامة على فئات RFM',
      'fr': 'Aperçu des Segments RFM',
    },
    'days': {'en': 'days', 'ar': 'يوم', 'fr': 'jours'},
    'grand_total': {
      'en': 'Grand Total',
      'ar': 'المجموع الكلي',
      'fr': 'Total Général',
    },
    'printed_on': {'en': 'Printed on', 'ar': 'طُبع في', 'fr': 'Imprimé le'},
    'segment_retail': {'en': 'Retail', 'ar': 'تجزئة', 'fr': 'Détail'},
    'segment_wholesale': {'en': 'Wholesale', 'ar': 'جملة', 'fr': 'Gros'},
    'segment_premium': {'en': 'Premium', 'ar': 'مميز', 'fr': 'Premium'},
    'rfm_champions': {'en': 'Champions', 'ar': 'أبطال', 'fr': 'Champions'},
    'rfm_loyal': {'en': 'Loyal', 'ar': 'مخلصون', 'fr': 'Fidèles'},
    'rfm_potential_loyal': {
      'en': 'Potential Loyal',
      'ar': 'محتمل الولاء',
      'fr': 'Potentiel Fidèle',
    },
    'rfm_new': {'en': 'New', 'ar': 'جديد', 'fr': 'Nouveau'},
    'rfm_promising': {'en': 'Promising', 'ar': 'واعد', 'fr': 'Prometteur'},
    'rfm_needs_attention': {
      'en': 'Needs Attention',
      'ar': 'يحتاج اهتمام',
      'fr': 'Attention Requise',
    },
    'rfm_about_to_sleep': {
      'en': 'About to Sleep',
      'ar': 'على وشك النوم',
      'fr': 'Sur le Point de Dormir',
    },
    'rfm_at_risk': {'en': 'At Risk', 'ar': 'في خطر', 'fr': 'À Risque'},
    'rfm_cant_lose': {
      'en': 'Can\'t Lose',
      'ar': 'لا يمكن خسارته',
      'fr': 'Ne Pas Perdre',
    },
    'rfm_hibernating': {
      'en': 'Hibernating',
      'ar': 'خامل',
      'fr': 'En Hibernation',
    },
    'rfm_lost': {'en': 'Lost', 'ar': 'مفقود', 'fr': 'Perdu'},
  };

  static String _t(String key, String lang) {
    return _translations[key]?[lang] ?? _translations[key]?['en'] ?? key;
  }

  static String _segmentLabelPdf(String segment, String lang) {
    switch (segment) {
      case 'retail':
        return _t('segment_retail', lang);
      case 'wholesale':
        return _t('segment_wholesale', lang);
      case 'premium':
        return _t('segment_premium', lang);
      default:
        return segment;
    }
  }

  static String _rfmLabelPdf(RfmSegment segment, String lang) {
    switch (segment) {
      case RfmSegment.champions:
        return _t('rfm_champions', lang);
      case RfmSegment.loyalCustomers:
        return _t('rfm_loyal', lang);
      case RfmSegment.potentialLoyalists:
        return _t('rfm_potential_loyal', lang);
      case RfmSegment.newCustomers:
        return _t('rfm_new', lang);
      case RfmSegment.promising:
        return _t('rfm_promising', lang);
      case RfmSegment.needsAttention:
        return _t('rfm_needs_attention', lang);
      case RfmSegment.aboutToSleep:
        return _t('rfm_about_to_sleep', lang);
      case RfmSegment.atRisk:
        return _t('rfm_at_risk', lang);
      case RfmSegment.cantLoseThem:
        return _t('rfm_cant_lose', lang);
      case RfmSegment.hibernating:
        return _t('rfm_hibernating', lang);
      case RfmSegment.lost:
        return _t('rfm_lost', lang);
    }
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
