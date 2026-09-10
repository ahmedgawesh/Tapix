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
import '../presentation/bloc/top_customers_bloc.dart';

class TopCustomersPdfService {
  static Future<void> printTopCustomersReport({
    required BuildContext context,
    required TopCustomersData data,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();

    final pdf = await _buildTopCustomersPdf(
      data: data,
      cs: cs,
      locale: locale,
      isRtl: isRtl,
      company: company,
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name:
          'TopCustomersReport_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> shareTopCustomersReport({
    required BuildContext context,
    required TopCustomersData data,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();

    final pdf = await _buildTopCustomersPdf(
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
          'TopCustomersReport_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  static Future<pw.Document> _buildTopCustomersPdf({
    required TopCustomersData data,
    required CurrencyService cs,
    required Locale locale,
    required bool isRtl,
    required CompanyProfile company,
  }) async {
    final fonts = await _loadFonts();
    final pdf = pw.Document();
    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final lang = locale.languageCode;

    final isRevenueView = data.view == TopCustomersViewType.byRevenue;
    final reportTitle = isRevenueView
        ? _t('top_customers_revenue', lang)
        : _t('top_customers_volume', lang);

    if (data.customers.isNotEmpty) {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          textDirection: dir,
          build: (pw.Context context) {
            return [
              _buildHeader(company, reportTitle, fonts, dir),
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
                    '${_t('total_revenue', lang)}: ${cs.formatCents(data.grandTotalRevenueCents)}',
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
                    '${_t('total_transactions', lang)}: ${data.grandTotalTransactions}',
                    style: pw.TextStyle(font: fonts.regular, fontSize: 10),
                  ),
                  pw.Text(
                    '${_t('total_quantity', lang)}: ${data.grandTotalQuantity}',
                    style: pw.TextStyle(font: fonts.regular, fontSize: 10),
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              // Data table
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 8),
                cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 8),
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
                  7: pw.Alignment.centerLeft,
                },
                headers: [
                  '#',
                  _t('customer', lang),
                  _t('segment', lang),
                  _t('revenue', lang),
                  _t('transactions', lang),
                  _t('quantity', lang),
                  _t('avg_order', lang),
                  _t('last_purchase', lang),
                ],
                data: data.customers.asMap().entries.map((entry) {
                  final idx = entry.key + 1;
                  final item = entry.value;
                  return [
                    '$idx',
                    item.customerName,
                    _segmentLabel(item.segment, lang),
                    cs.formatCents(item.totalRevenueCents),
                    '${item.transactionCount}',
                    '${item.totalQuantity}',
                    cs.formatCents(item.averageOrderCents),
                    item.lastPurchaseDate != null
                        ? DateFormat(
                            'dd/MM/yyyy',
                          ).format(item.lastPurchaseDate!)
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
                      cs.formatCents(data.grandTotalRevenueCents),
                      style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                    ),
                  ],
                ),
              ),
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
    }

    return pdf;
  }

  // ═══════════════════════════════════════════════════════
  // 3-LANGUAGE TRANSLATIONS FOR PDF
  // ═══════════════════════════════════════════════════════

  static const _translations = {
    'top_customers_revenue': {
      'en': 'Top Customers by Revenue',
      'ar': 'أفضل العملاء حسب الإيرادات',
      'fr': 'Meilleurs Clients par Chiffre d\'Affaires',
    },
    'top_customers_volume': {
      'en': 'Top Customers by Volume',
      'ar': 'أفضل العملاء حسب الحجم',
      'fr': 'Meilleurs Clients par Volume',
    },
    'period': {'en': 'Period', 'ar': 'الفترة', 'fr': 'Période'},
    'total_revenue': {
      'en': 'Total Revenue',
      'ar': 'إجمالي الإيرادات',
      'fr': 'Chiffre d\'Affaires Total',
    },
    'total_customers': {
      'en': 'Total Customers',
      'ar': 'إجمالي العملاء',
      'fr': 'Total Clients',
    },
    'total_transactions': {
      'en': 'Total Transactions',
      'ar': 'إجمالي المعاملات',
      'fr': 'Total Transactions',
    },
    'total_quantity': {
      'en': 'Total Quantity',
      'ar': 'إجمالي الكمية',
      'fr': 'Quantité Totale',
    },
    'customer': {'en': 'Customer', 'ar': 'العميل', 'fr': 'Client'},
    'segment': {'en': 'Segment', 'ar': 'الفئة', 'fr': 'Segment'},
    'revenue': {
      'en': 'Revenue',
      'ar': 'الإيرادات',
      'fr': 'Chiffre d\'Affaires',
    },
    'transactions': {
      'en': 'Transactions',
      'ar': 'المعاملات',
      'fr': 'Transactions',
    },
    'quantity': {'en': 'Qty', 'ar': 'الكمية', 'fr': 'Qté'},
    'avg_order': {
      'en': 'Avg Order',
      'ar': 'متوسط الطلب',
      'fr': 'Commande Moy.',
    },
    'last_purchase': {
      'en': 'Last Purchase',
      'ar': 'آخر شراء',
      'fr': 'Dernier Achat',
    },
    'grand_total': {
      'en': 'Grand Total',
      'ar': 'المجموع الكلي',
      'fr': 'Total Général',
    },
    'printed_on': {'en': 'Printed on', 'ar': 'طُبع في', 'fr': 'Imprimé le'},
    'segment_retail': {'en': 'Retail', 'ar': 'تجزئة', 'fr': 'Détail'},
    'segment_wholesale': {'en': 'Wholesale', 'ar': 'جملة', 'fr': 'Gros'},
    'segment_premium': {'en': 'Premium', 'ar': 'مميز', 'fr': 'Premium'},
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
