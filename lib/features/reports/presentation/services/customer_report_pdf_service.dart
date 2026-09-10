import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../../settings/data/services/company_profile_service.dart';
import '../../../settings/domain/entities/company_profile.dart';
import '../bloc/customer_reports_bloc.dart';

/// Generates PDF reports for the Customer Reports screen.
/// Supports: print all customers summary, share all, print single customer.
class CustomerReportPdfService {
  // ── Print all customers summary ──
  static Future<void> printAllCustomersReport({
    required BuildContext context,
    required CustomerReportsData data,
  }) async {
    final pdf = await _buildAllCustomersPdf(context, data);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'CustomerReport_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  // ── Share all customers summary ──
  static Future<void> shareAllCustomersReport({
    required BuildContext context,
    required CustomerReportsData data,
  }) async {
    final pdf = await _buildAllCustomersPdf(context, data);
    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'CustomerReport_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  // ── Print single customer report ──
  static Future<void> printSingleCustomerReport({
    required BuildContext context,
    required CustomerBalanceItem customer,
  }) async {
    final pdf = await _buildSingleCustomerPdf(context, customer);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name:
          'Customer_${customer.customerName}_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  // ── Share single customer report ──
  static Future<void> shareSingleCustomerReport({
    required BuildContext context,
    required CustomerBalanceItem customer,
  }) async {
    final pdf = await _buildSingleCustomerPdf(context, customer);
    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'Customer_${customer.customerName}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  // ═══════════════════════════════════════════════════════
  // BUILD ALL CUSTOMERS PDF
  // ═══════════════════════════════════════════════════════

  static Future<pw.Document> _buildAllCustomersPdf(
    BuildContext context,
    CustomerReportsData data,
  ) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final lang = locale.languageCode;
    final company = await sl<CompanyProfileService>().getProfile();
    final fonts = await _loadFonts();
    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: dir,
        build: (pw.Context ctx) {
          return [
            _buildHeader(company, _t('customer_report', lang), fonts, dir),
            pw.SizedBox(height: 12),

            // Summary table
            pw.Text(
              _t('summary', lang),
              style: pw.TextStyle(font: fonts.bold, fontSize: 12),
            ),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 9),
              cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 9),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
              headers: [
                _t('total_receivables', lang),
                _t('total_payables', lang),
                _t('opening_debit', lang),
                _t('opening_credit', lang),
                _t('total_discounts', lang),
                _t('total_payments', lang),
              ],
              data: [
                [
                  cs.formatCents(data.totalReceivablesCents),
                  cs.formatCents(data.totalPayablesCents),
                  cs.formatCents(data.totalOpeningDebitCents),
                  cs.formatCents(data.totalOpeningCreditCents),
                  cs.formatCents(data.totalDiscountsCents),
                  cs.formatCents(data.totalPaymentsCents),
                ],
              ],
            ),
            pw.SizedBox(height: 16),

            // Per-customer table
            pw.Text(
              '${_t('active_customers', lang)}: ${data.activeCustomerCount}',
              style: pw.TextStyle(font: fonts.bold, fontSize: 11),
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
                1: pw.Alignment.centerRight,
                2: pw.Alignment.centerRight,
                3: pw.Alignment.centerRight,
                4: pw.Alignment.centerRight,
                5: pw.Alignment.centerRight,
                6: pw.Alignment.centerRight,
              },
              headers: [
                _t('customer', lang),
                _t('opening_balance', lang),
                _t('total_sales', lang),
                _t('total_payments', lang),
                _t('total_discounts', lang),
                _t('total_returns', lang),
                _t('current_balance', lang),
              ],
              data: data.customers
                  .map(
                    (c) => [
                      c.customerName,
                      cs.formatCents(c.openingBalanceCents),
                      cs.formatCents(c.totalSalesCents),
                      cs.formatCents(c.totalPaymentsCents),
                      cs.formatCents(c.totalDiscountsCents),
                      cs.formatCents(c.totalReturnsCents),
                      cs.formatCents(c.currentBalanceCents),
                    ],
                  )
                  .toList(),
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

    return pdf;
  }

  // ═══════════════════════════════════════════════════════
  // BUILD SINGLE CUSTOMER PDF
  // ═══════════════════════════════════════════════════════

  static Future<pw.Document> _buildSingleCustomerPdf(
    BuildContext context,
    CustomerBalanceItem customer,
  ) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final lang = locale.languageCode;
    final company = await sl<CompanyProfileService>().getProfile();
    final fonts = await _loadFonts();
    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        textDirection: dir,
        build: (pw.Context ctx) {
          final bal = customer.currentBalanceCents;
          final isReceivable = bal > 0;
          final isZero = bal == 0;
          final balLabel = isZero
              ? _t('balance_settled', lang)
              : isReceivable
              ? _t('balance_receivable', lang)
              : _t('balance_payable', lang);

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildHeader(company, _t('customer_report', lang), fonts, dir),
              pw.SizedBox(height: 12),

              // Customer name
              pw.Text(
                '${_t('customer', lang)}: ${customer.customerName}',
                style: pw.TextStyle(font: fonts.bold, fontSize: 13),
              ),
              pw.SizedBox(height: 12),

              // Balance breakdown
              _buildRow(
                _t('opening_balance', lang),
                cs.formatCents(customer.openingBalanceCents),
                fonts,
              ),
              _buildRow(
                _t('total_sales', lang),
                cs.formatCents(customer.totalSalesCents),
                fonts,
              ),
              _buildRow(
                _t('total_payments', lang),
                cs.formatCents(customer.totalPaymentsCents),
                fonts,
              ),
              _buildRow(
                _t('total_discounts', lang),
                cs.formatCents(customer.totalDiscountsCents),
                fonts,
              ),
              _buildRow(
                _t('total_returns', lang),
                cs.formatCents(customer.totalReturnsCents),
                fonts,
              ),
              pw.Divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    _t('current_balance', lang),
                    style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                  ),
                  pw.Text(
                    cs.formatCents(bal),
                    style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                  ),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                balLabel,
                style: pw.TextStyle(
                  font: fonts.regular,
                  fontSize: 9,
                  color: PdfColors.grey600,
                ),
              ),

              pw.SizedBox(height: 24),
              pw.Divider(),
              pw.Text(
                '${_t('printed_on', lang)}: ${DateFormat('dd/MM/yyyy').add_jm().format(DateTime.now())}',
                style: pw.TextStyle(
                  font: fonts.regular,
                  fontSize: 8,
                  color: PdfColors.grey600,
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf;
  }

  // ═══════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════

  static pw.Widget _buildRow(String label, String value, _PdfFonts fonts) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(font: fonts.regular, fontSize: 10),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(font: fonts.regular, fontSize: 10),
          ),
        ],
      ),
    );
  }

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

  // ═══════════════════════════════════════════════════════
  // 3-LANGUAGE TRANSLATIONS FOR PDF
  // ═══════════════════════════════════════════════════════

  static const _translations = {
    'customer_report': {
      'en': 'Customer Report',
      'ar': 'تقرير العملاء',
      'fr': 'Rapport Clients',
    },
    'summary': {'en': 'Summary', 'ar': 'ملخص', 'fr': 'Résumé'},
    'total_receivables': {
      'en': 'Total Receivables',
      'ar': 'إجمالي المستحقات لنا',
      'fr': 'Total Créances',
    },
    'total_payables': {
      'en': 'Total Payables',
      'ar': 'إجمالي المستحقات علينا',
      'fr': 'Total Dettes',
    },
    'opening_debit': {
      'en': 'Opening Debit',
      'ar': 'رصيد افتتاحي مدين',
      'fr': 'Débit d\'Ouverture',
    },
    'opening_credit': {
      'en': 'Opening Credit',
      'ar': 'رصيد افتتاحي دائن',
      'fr': 'Crédit d\'Ouverture',
    },
    'total_discounts': {
      'en': 'Total Discounts',
      'ar': 'إجمالي الخصومات',
      'fr': 'Total Remises',
    },
    'total_payments': {
      'en': 'Total Payments',
      'ar': 'إجمالي الدفعات',
      'fr': 'Total Paiements',
    },
    'active_customers': {
      'en': 'Active Customers',
      'ar': 'العملاء النشطون',
      'fr': 'Clients Actifs',
    },
    'customer': {'en': 'Customer', 'ar': 'العميل', 'fr': 'Client'},
    'opening_balance': {
      'en': 'Opening Balance',
      'ar': 'الرصيد الافتتاحي',
      'fr': 'Solde d\'Ouverture',
    },
    'total_sales': {
      'en': 'Total Sales',
      'ar': 'إجمالي المبيعات',
      'fr': 'Total Ventes',
    },
    'total_returns': {
      'en': 'Total Returns',
      'ar': 'إجمالي المرتجعات',
      'fr': 'Total Retours',
    },
    'current_balance': {
      'en': 'Current Balance',
      'ar': 'الرصيد الحالي',
      'fr': 'Solde Actuel',
    },
    'balance_settled': {
      'en': 'Balance settled',
      'ar': 'الرصيد مسدد',
      'fr': 'Solde réglé',
    },
    'balance_receivable': {
      'en': 'Customer owes you',
      'ar': 'العميل مدين لك',
      'fr': 'Le client vous doit',
    },
    'balance_payable': {
      'en': 'You owe the customer',
      'ar': 'أنت مدين للعميل',
      'fr': 'Vous devez au client',
    },
    'printed_on': {'en': 'Printed on', 'ar': 'طُبع في', 'fr': 'Imprimé le'},
  };

  static String _t(String key, String lang) {
    return _translations[key]?[lang] ?? _translations[key]?['en'] ?? key;
  }
}

class _PdfFonts {
  final pw.Font regular;
  final pw.Font bold;

  _PdfFonts({required this.regular, required this.bold});
}
