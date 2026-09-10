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
import '../presentation/bloc/supplier_analysis_report_bloc.dart';

class SupplierAnalysisPdfService {
  static Future<void> printSupplierAnalysisReport({
    required BuildContext context,
    required SupplierAnalysisReportData data,
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
          'SupplierAnalysisReport_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> shareSupplierAnalysisReport({
    required BuildContext context,
    required SupplierAnalysisReportData data,
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
          'SupplierAnalysisReport_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  static Future<pw.Document> _buildPdf({
    required SupplierAnalysisReportData data,
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
              _t('supplier_analysis_report', lang),
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
                  '${_t('total_purchases', lang)}: ${cs.formatCents(data.grandTotalPurchasesCents)}',
                  style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                ),
                pw.Text(
                  '${_t('total_returns', lang)}: ${cs.formatCents(data.grandTotalReturnsCents)}',
                  style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                ),
                pw.Text(
                  '${_t('total_payments', lang)}: ${cs.formatCents(data.grandTotalPaymentsCents)}',
                  style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '${_t('avg_return_rate', lang)}: ${data.avgReturnRatePercent.toStringAsFixed(1)}%',
                  style: pw.TextStyle(font: fonts.regular, fontSize: 10),
                ),
                pw.Text(
                  '${_t('avg_settlement', lang)}: ${data.avgSettlementRatioPercent.toStringAsFixed(1)}%',
                  style: pw.TextStyle(font: fonts.regular, fontSize: 10),
                ),
                pw.Text(
                  '${_t('avg_payment_days', lang)}: ${data.avgPaymentDays.toStringAsFixed(0)} ${_t('days', lang)}',
                  style: pw.TextStyle(font: fonts.regular, fontSize: 10),
                ),
                pw.Text(
                  '${_t('total_suppliers', lang)}: ${data.totalSuppliers}',
                  style: pw.TextStyle(font: fonts.regular, fontSize: 10),
                ),
              ],
            ),
            pw.SizedBox(height: 12),

            // Supplier analysis data table
            if (data.suppliers.isNotEmpty) ...[
              pw.Text(
                _t('supplier_analysis_details', lang),
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
                  4: pw.Alignment.centerRight,
                  5: pw.Alignment.center,
                  6: pw.Alignment.centerRight,
                  7: pw.Alignment.center,
                  8: pw.Alignment.center,
                  9: pw.Alignment.centerRight,
                },
                headers: [
                  '#',
                  _t('supplier', lang),
                  _t('purchases', lang),
                  _t('orders', lang),
                  _t('returns', lang),
                  _t('return_rate', lang),
                  _t('payments', lang),
                  _t('settlement', lang),
                  _t('payment_days', lang),
                  _t('avg_order', lang),
                ],
                data: data.suppliers.asMap().entries.map((entry) {
                  final idx = entry.key + 1;
                  final item = entry.value;
                  return [
                    '$idx',
                    item.supplierName,
                    cs.formatCents(item.totalPurchasesCents),
                    '${item.purchaseCount}',
                    cs.formatCents(item.totalReturnsCents),
                    '${item.returnRatePercent.toStringAsFixed(1)}%',
                    cs.formatCents(item.totalPaymentsCents),
                    '${item.settlementRatioPercent.toStringAsFixed(1)}%',
                    item.avgPaymentDays.toStringAsFixed(0),
                    cs.formatCents(item.avgOrderValueCents),
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
                          '${_t('purchases', lang)}: ${cs.formatCents(data.grandTotalPurchasesCents)}',
                          style: pw.TextStyle(font: fonts.regular, fontSize: 8),
                        ),
                        pw.SizedBox(width: 12),
                        pw.Text(
                          '${_t('returns', lang)}: ${cs.formatCents(data.grandTotalReturnsCents)}',
                          style: pw.TextStyle(font: fonts.regular, fontSize: 8),
                        ),
                        pw.SizedBox(width: 12),
                        pw.Text(
                          '${_t('payments', lang)}: ${cs.formatCents(data.grandTotalPaymentsCents)}',
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
    'supplier_analysis_report': {
      'en': 'Supplier Analysis Report',
      'ar': 'تقرير تحليل الموردين',
      'fr': 'Rapport d\'Analyse Fournisseurs',
    },
    'period': {'en': 'Period', 'ar': 'الفترة', 'fr': 'Période'},
    'total_purchases': {
      'en': 'Total Purchases',
      'ar': 'إجمالي المشتريات',
      'fr': 'Total Achats',
    },
    'total_returns': {
      'en': 'Total Returns',
      'ar': 'إجمالي المرتجعات',
      'fr': 'Total Retours',
    },
    'total_payments': {
      'en': 'Total Payments',
      'ar': 'إجمالي المدفوعات',
      'fr': 'Total Paiements',
    },
    'avg_return_rate': {
      'en': 'Avg Return Rate',
      'ar': 'متوسط نسبة المرتجعات',
      'fr': 'Taux Retour Moyen',
    },
    'avg_settlement': {
      'en': 'Avg Settlement',
      'ar': 'متوسط التسوية',
      'fr': 'Règlement Moyen',
    },
    'avg_payment_days': {
      'en': 'Avg Payment Days',
      'ar': 'متوسط أيام الدفع',
      'fr': 'Jours Paiement Moyen',
    },
    'total_suppliers': {
      'en': 'Total Suppliers',
      'ar': 'إجمالي الموردين',
      'fr': 'Total Fournisseurs',
    },
    'supplier_analysis_details': {
      'en': 'Supplier Analysis Details',
      'ar': 'تفاصيل تحليل الموردين',
      'fr': 'Détails Analyse Fournisseurs',
    },
    'supplier': {'en': 'Supplier', 'ar': 'المورد', 'fr': 'Fournisseur'},
    'purchases': {'en': 'Purchases', 'ar': 'المشتريات', 'fr': 'Achats'},
    'orders': {'en': 'Orders', 'ar': 'الطلبات', 'fr': 'Commandes'},
    'returns': {'en': 'Returns', 'ar': 'المرتجعات', 'fr': 'Retours'},
    'return_rate': {
      'en': 'Return Rate',
      'ar': 'نسبة المرتجعات',
      'fr': 'Taux Retour',
    },
    'payments': {'en': 'Payments', 'ar': 'المدفوعات', 'fr': 'Paiements'},
    'settlement': {'en': 'Settlement', 'ar': 'التسوية', 'fr': 'Règlement'},
    'payment_days': {'en': 'Pay Days', 'ar': 'أيام الدفع', 'fr': 'Jours Paie'},
    'avg_order': {
      'en': 'Avg Order',
      'ar': 'متوسط الطلب',
      'fr': 'Commande Moy.',
    },
    'days': {'en': 'days', 'ar': 'يوم', 'fr': 'jours'},
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
