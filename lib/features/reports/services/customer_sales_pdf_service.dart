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
import '../presentation/bloc/customer_sales_report_bloc.dart';

class CustomerSalesPdfService {
  static Future<void> printCustomerSalesReport({
    required BuildContext context,
    required CustomerSalesReportData data,
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
          'CustomerSalesReport_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> shareCustomerSalesReport({
    required BuildContext context,
    required CustomerSalesReportData data,
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
          'CustomerSalesReport_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  static Future<pw.Document> _buildPdf({
    required CustomerSalesReportData data,
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
                company, _t('customer_sales_report', lang), fonts, dir),
            pw.SizedBox(height: 8),
            pw.Text(
              '${_t('period', lang)}: ${DateFormat.yMMMd().format(data.dateRange.startDate)} — ${DateFormat.yMMMd().format(data.dateRange.endDate)}',
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
                  '${_t('total_customers', lang)}: ${data.uniqueCustomerCount}',
                  style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '${_t('total_invoices', lang)}: ${data.grandTotalInvoices}',
                  style: pw.TextStyle(font: fonts.regular, fontSize: 10),
                ),
                pw.Text(
                  '${_t('total_quantity', lang)}: ${data.grandTotalQuantity}',
                  style: pw.TextStyle(font: fonts.regular, fontSize: 10),
                ),
              ],
            ),
            pw.SizedBox(height: 12),

            // Customer sales data table
            if (data.customers.isNotEmpty) ...[
              pw.Text(
                _t('customer_sales_details', lang),
                style: pw.TextStyle(font: fonts.bold, fontSize: 12),
              ),
              pw.SizedBox(height: 6),
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 8),
                cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 8),
                headerDecoration:
                    const pw.BoxDecoration(color: PdfColors.grey200),
                cellAlignments: {
                  0: pw.Alignment.center,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.centerLeft,
                  3: pw.Alignment.centerRight,
                  4: pw.Alignment.centerRight,
                  5: pw.Alignment.centerRight,
                  6: pw.Alignment.centerRight,
                  7: pw.Alignment.centerLeft,
                },
                headers: [
                  '#',
                  _t('customer', lang),
                  _t('segment', lang),
                  _t('total_sales', lang),
                  _t('invoices', lang),
                  _t('quantity', lang),
                  _t('avg_order', lang),
                  _t('last_sale', lang),
                ],
                data: data.customers.asMap().entries.map((entry) {
                  final idx = entry.key + 1;
                  final item = entry.value;
                  return [
                    '$idx',
                    item.customerName,
                    _segmentLabel(item.segment, lang),
                    cs.formatCents(item.totalSalesCents),
                    '${item.invoiceCount}',
                    '${item.totalQuantity}',
                    cs.formatCents(item.averageOrderCents),
                    item.lastSaleDate != null
                        ? DateFormat.yMd().format(item.lastSaleDate!)
                        : '-',
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
                      cs.formatCents(data.grandTotalSalesCents),
                      style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],

            pw.SizedBox(height: 16),
            pw.Divider(),
            pw.Text(
              '${_t('printed_on', lang)}: ${DateFormat.yMMMd().add_jm().format(DateTime.now())}',
              style: pw.TextStyle(
                  font: fonts.regular,
                  fontSize: 8,
                  color: PdfColors.grey600),
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
    'customer_sales_report': {
      'en': 'Customer Sales Report',
      'ar': 'تقرير مبيعات العملاء',
      'fr': 'Rapport des Ventes par Client',
    },
    'period': {'en': 'Period', 'ar': 'الفترة', 'fr': 'Période'},
    'total_sales': {
      'en': 'Total Sales',
      'ar': 'إجمالي المبيعات',
      'fr': 'Total des Ventes',
    },
    'total_customers': {
      'en': 'Total Customers',
      'ar': 'إجمالي العملاء',
      'fr': 'Total Clients',
    },
    'total_invoices': {
      'en': 'Total Invoices',
      'ar': 'إجمالي الفواتير',
      'fr': 'Total Factures',
    },
    'total_quantity': {
      'en': 'Total Quantity',
      'ar': 'إجمالي الكمية',
      'fr': 'Quantité Totale',
    },
    'customer_sales_details': {
      'en': 'Customer Sales Details',
      'ar': 'تفاصيل مبيعات العملاء',
      'fr': 'Détails des Ventes par Client',
    },
    'customer': {'en': 'Customer', 'ar': 'العميل', 'fr': 'Client'},
    'segment': {'en': 'Segment', 'ar': 'الفئة', 'fr': 'Segment'},
    'invoices': {'en': 'Invoices', 'ar': 'الفواتير', 'fr': 'Factures'},
    'quantity': {'en': 'Qty', 'ar': 'الكمية', 'fr': 'Qté'},
    'avg_order': {
      'en': 'Avg Order',
      'ar': 'متوسط الطلب',
      'fr': 'Commande Moy.',
    },
    'last_sale': {
      'en': 'Last Sale',
      'ar': 'آخر بيع',
      'fr': 'Dernière Vente',
    },
    'grand_total': {
      'en': 'Grand Total',
      'ar': 'المجموع الكلي',
      'fr': 'Total Général',
    },
    'printed_on': {
      'en': 'Printed on',
      'ar': 'طُبع في',
      'fr': 'Imprimé le',
    },
    'segment_retail': {
      'en': 'Retail',
      'ar': 'تجزئة',
      'fr': 'Détail',
    },
    'segment_wholesale': {
      'en': 'Wholesale',
      'ar': 'جملة',
      'fr': 'Gros',
    },
    'segment_premium': {
      'en': 'Premium',
      'ar': 'مميز',
      'fr': 'Premium',
    },
  };

  static String _t(String key, String lang) {
    return _translations[key]?[lang] ?? _translations[key]?['en'] ?? key;
  }

  static String _segmentLabel(String segment, String lang) {
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
                color: PdfColors.grey600),
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
      final regularData =
          await rootBundle.load('assets/fonts/IBMPlexSansArabic-Regular.ttf');
      final boldData =
          await rootBundle.load('assets/fonts/IBMPlexSansArabic-Bold.ttf');
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
