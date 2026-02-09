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
import '../presentation/bloc/customer_payment_reports_bloc.dart';

class CustomerPaymentPdfService {
  static Future<void> printCustomerPaymentReport({
    required BuildContext context,
    required CustomerPaymentReportsData data,
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
          'CustomerPaymentReport_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> shareCustomerPaymentReport({
    required BuildContext context,
    required CustomerPaymentReportsData data,
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
          'CustomerPaymentReport_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  static Future<pw.Document> _buildPdf({
    required CustomerPaymentReportsData data,
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
            _buildHeader(company, _t('customer_payment_report', lang), fonts, dir),
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
                  '${_t('total_payments', lang)}: ${cs.formatCents(data.totalAmountCents)}',
                  style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                ),
                pw.Text(
                  '${_t('paying_customers', lang)}: ${data.uniqueCustomerCount}',
                  style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              '${_t('total_transactions', lang)}: ${data.transactionCount}',
              style: pw.TextStyle(font: fonts.regular, fontSize: 10),
            ),
            pw.SizedBox(height: 12),

            // Payment method summary table
            if (data.methodSummaries.isNotEmpty) ...[
              pw.Text(
                _t('payment_method_breakdown', lang),
                style: pw.TextStyle(font: fonts.bold, fontSize: 12),
              ),
              pw.SizedBox(height: 6),
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 9),
                cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 9),
                headerDecoration:
                    const pw.BoxDecoration(color: PdfColors.grey200),
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerRight,
                  2: pw.Alignment.centerRight,
                  3: pw.Alignment.centerRight,
                },
                headers: [
                  _t('payment_method', lang),
                  _t('amount', lang),
                  _t('count', lang),
                  _t('percentage', lang),
                ],
                data: data.methodSummaries.map((s) {
                  return [
                    _methodLabel(s.method, lang),
                    cs.formatCents(s.amountCents),
                    '${s.transactionCount}',
                    '${s.percentage.toStringAsFixed(1)}%',
                  ];
                }).toList(),
              ),
              pw.SizedBox(height: 4),
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
                      cs.formatCents(data.totalAmountCents),
                      style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),
            ],

            // Payment details table
            if (data.details.isNotEmpty) ...[
              pw.Text(
                _t('payment_details', lang),
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
                  4: pw.Alignment.centerLeft,
                },
                headers: [
                  _t('date', lang),
                  _t('customer', lang),
                  _t('type', lang),
                  _t('amount', lang),
                  _t('description', lang),
                ],
                data: data.details.map((d) {
                  return [
                    DateFormat.yMd().format(d.transactionDate),
                    d.customerName,
                    _typeLabel(d.transactionType, lang),
                    cs.formatCents(d.amountCents.abs()),
                    d.description ?? '-',
                  ];
                }).toList(),
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
    'customer_payment_report': {
      'en': 'Customer Payment Report',
      'ar': 'تقرير مدفوعات العملاء',
      'fr': 'Rapport des Paiements Clients',
    },
    'period': {'en': 'Period', 'ar': 'الفترة', 'fr': 'Période'},
    'total_payments': {
      'en': 'Total Payments',
      'ar': 'إجمالي المدفوعات',
      'fr': 'Total des Paiements',
    },
    'paying_customers': {
      'en': 'Paying Customers',
      'ar': 'العملاء الدافعون',
      'fr': 'Clients Payants',
    },
    'total_transactions': {
      'en': 'Total Transactions',
      'ar': 'إجمالي المعاملات',
      'fr': 'Total Transactions',
    },
    'payment_method_breakdown': {
      'en': 'Payment Method Breakdown',
      'ar': 'تفصيل طرق الدفع',
      'fr': 'Répartition par Méthode de Paiement',
    },
    'payment_method': {
      'en': 'Payment Method',
      'ar': 'طريقة الدفع',
      'fr': 'Méthode de Paiement',
    },
    'amount': {'en': 'Amount', 'ar': 'المبلغ', 'fr': 'Montant'},
    'count': {'en': 'Count', 'ar': 'العدد', 'fr': 'Nombre'},
    'percentage': {'en': '%', 'ar': '%', 'fr': '%'},
    'grand_total': {
      'en': 'Grand Total',
      'ar': 'المجموع الكلي',
      'fr': 'Total Général',
    },
    'payment_details': {
      'en': 'Payment Details',
      'ar': 'تفاصيل المدفوعات',
      'fr': 'Détails des Paiements',
    },
    'date': {'en': 'Date', 'ar': 'التاريخ', 'fr': 'Date'},
    'customer': {'en': 'Customer', 'ar': 'العميل', 'fr': 'Client'},
    'type': {'en': 'Type', 'ar': 'النوع', 'fr': 'Type'},
    'description': {
      'en': 'Description',
      'ar': 'الوصف',
      'fr': 'Description',
    },
    'printed_on': {
      'en': 'Printed on',
      'ar': 'طُبع في',
      'fr': 'Imprimé le',
    },
    'method_cash': {'en': 'Cash', 'ar': 'نقدي', 'fr': 'Espèces'},
    'method_card': {'en': 'Card', 'ar': 'بطاقة', 'fr': 'Carte'},
    'method_bank': {
      'en': 'Bank Transfer',
      'ar': 'تحويل بنكي',
      'fr': 'Virement Bancaire',
    },
    'method_credit': {
      'en': 'Credit (Pay Later)',
      'ar': 'آجل (ادفع لاحقاً)',
      'fr': 'Crédit (Payer Plus Tard)',
    },
    'type_payment': {'en': 'Payment', 'ar': 'دفعة', 'fr': 'Paiement'},
    'type_receipt': {'en': 'Receipt', 'ar': 'إيصال', 'fr': 'Reçu'},
    'type_settlement': {
      'en': 'Settlement',
      'ar': 'تسوية',
      'fr': 'Règlement',
    },
  };

  static String _t(String key, String lang) {
    return _translations[key]?[lang] ?? _translations[key]?['en'] ?? key;
  }

  static String _methodLabel(String method, String lang) {
    switch (method.toLowerCase()) {
      case 'cash':
        return _t('method_cash', lang);
      case 'card':
        return _t('method_card', lang);
      case 'bank':
      case 'bank_transfer':
        return _t('method_bank', lang);
      case 'credit':
      case 'pay_later':
        return _t('method_credit', lang);
      case 'payment':
        return _t('type_payment', lang);
      case 'receipt':
        return _t('type_receipt', lang);
      case 'settlement':
        return _t('type_settlement', lang);
      default:
        return method;
    }
  }

  static String _typeLabel(String type, String lang) {
    switch (type) {
      case 'payment':
        return _t('type_payment', lang);
      case 'receipt':
        return _t('type_receipt', lang);
      case 'settlement':
        return _t('type_settlement', lang);
      default:
        return type;
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
