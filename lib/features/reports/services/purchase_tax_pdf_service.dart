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
import '../presentation/bloc/purchase_tax_report_bloc.dart';

class PurchaseTaxPdfService {
  static Future<void> printPurchaseTaxReport({
    required BuildContext context,
    required PurchaseTaxReportData data,
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
          'PurchaseTaxReport_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> sharePurchaseTaxReport({
    required BuildContext context,
    required PurchaseTaxReportData data,
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
          'PurchaseTaxReport_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  static Future<pw.Document> _buildPdf({
    required PurchaseTaxReportData data,
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
            _buildHeader(company, _t('purchase_tax_report', lang), fonts, dir),
            pw.SizedBox(height: 8),
            pw.Text(
              '${_t('period', lang)}: ${DateFormat('dd/MM/yyyy').format(data.dateRange.startDate)} — ${DateFormat('dd/MM/yyyy').format(data.dateRange.endDate)}',
              style: pw.TextStyle(font: fonts.regular, fontSize: 10),
            ),
            pw.SizedBox(height: 12),

            // Summary box
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  _summaryCol(
                    _t('total_taxable', lang),
                    cs.formatCents(data.totalTaxableCents),
                    fonts,
                  ),
                  _summaryCol(
                    _t('tax_paid', lang),
                    cs.formatCents(data.totalTaxPaidCents),
                    fonts,
                  ),
                  _summaryCol(
                    _t('tax_returns', lang),
                    '- ${cs.formatCents(data.returnTaxCents)}',
                    fonts,
                  ),
                  _summaryCol(
                    _t('net_tax', lang),
                    cs.formatCents(data.netTaxCents),
                    fonts,
                    bold: true,
                  ),
                  _summaryCol(
                    _t('invoices', lang),
                    '${data.invoiceCount}',
                    fonts,
                  ),
                  _summaryCol(
                    _t('returns', lang),
                    '${data.returnCount}',
                    fonts,
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),

            // Purchase invoices table
            if (data.invoices.isNotEmpty) ...[
              pw.Text(
                _t('purchase_invoices', lang),
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
                  0: pw.Alignment.center,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.centerLeft,
                  3: pw.Alignment.centerLeft,
                  4: pw.Alignment.centerRight,
                  5: pw.Alignment.centerRight,
                  6: pw.Alignment.centerRight,
                  7: pw.Alignment.centerRight,
                },
                headers: [
                  '#',
                  _t('invoice', lang),
                  _t('supplier', lang),
                  _t('date', lang),
                  _t('subtotal', lang),
                  _t('taxable', lang),
                  _t('tax', lang),
                  _t('total', lang),
                ],
                data: data.invoices.asMap().entries.map((entry) {
                  final idx = entry.key + 1;
                  final inv = entry.value;
                  return [
                    '$idx',
                    inv.purchaseNumber,
                    inv.supplierName ?? '-',
                    DateFormat('dd/MM/yyyy').format(inv.purchaseDate),
                    cs.formatCents(inv.subtotalCents),
                    cs.formatCents(inv.taxableCents),
                    cs.formatCents(inv.taxCents),
                    cs.formatCents(inv.totalCents),
                  ];
                }).toList(),
              ),
              pw.SizedBox(height: 6),
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      '${_t('total', lang)}:',
                      style: pw.TextStyle(font: fonts.bold, fontSize: 10),
                    ),
                    pw.Text(
                      '${_t('taxable', lang)}: ${cs.formatCents(data.totalTaxableCents)}  |  '
                      '${_t('tax', lang)}: ${cs.formatCents(data.totalTaxPaidCents)}  |  '
                      '${_t('total', lang)}: ${cs.formatCents(data.totalPurchasesCents)}',
                      style: pw.TextStyle(font: fonts.bold, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],

            // Returns table
            if (data.returns.isNotEmpty) ...[
              pw.SizedBox(height: 16),
              pw.Text(
                _t('purchase_returns', lang),
                style: pw.TextStyle(font: fonts.bold, fontSize: 12),
              ),
              pw.SizedBox(height: 6),
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 8),
                cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 8),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.red50,
                ),
                cellAlignments: {
                  0: pw.Alignment.center,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.centerLeft,
                  3: pw.Alignment.centerLeft,
                  4: pw.Alignment.centerRight,
                  5: pw.Alignment.centerRight,
                },
                headers: [
                  '#',
                  _t('return_number', lang),
                  _t('supplier', lang),
                  _t('date', lang),
                  _t('tax_refunded', lang),
                  _t('total', lang),
                ],
                data: data.returns.asMap().entries.map((entry) {
                  final idx = entry.key + 1;
                  final ret = entry.value;
                  return [
                    '$idx',
                    ret.returnNumber,
                    ret.supplierName ?? '-',
                    DateFormat('dd/MM/yyyy').format(ret.returnDate),
                    cs.formatCents(ret.taxCents),
                    cs.formatCents(ret.totalCents),
                  ];
                }).toList(),
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
    'purchase_tax_report': {
      'en': 'Purchase Tax Report',
      'ar': 'تقرير ضرائب المشتريات',
      'fr': 'Rapport de Taxe sur les Achats',
    },
    'period': {'en': 'Period', 'ar': 'الفترة', 'fr': 'Période'},
    'total_taxable': {
      'en': 'Total Taxable',
      'ar': 'إجمالي الخاضع للضريبة',
      'fr': 'Total Imposable',
    },
    'tax_paid': {
      'en': 'Tax Paid',
      'ar': 'الضريبة المدفوعة',
      'fr': 'Taxe Payée',
    },
    'tax_returns': {
      'en': 'Tax Returns',
      'ar': 'ضريبة المرتجعات',
      'fr': 'Taxe Retours',
    },
    'net_tax': {'en': 'Net Tax', 'ar': 'صافي الضريبة', 'fr': 'Taxe Nette'},
    'invoices': {'en': 'Invoices', 'ar': 'الفواتير', 'fr': 'Factures'},
    'returns': {'en': 'Returns', 'ar': 'المرتجعات', 'fr': 'Retours'},
    'purchase_invoices': {
      'en': 'Purchase Invoices',
      'ar': 'فواتير المشتريات',
      'fr': 'Factures d\'Achat',
    },
    'purchase_returns': {
      'en': 'Purchase Returns',
      'ar': 'مرتجعات المشتريات',
      'fr': 'Retours d\'Achat',
    },
    'invoice': {'en': 'Invoice #', 'ar': 'رقم الفاتورة', 'fr': 'N° Facture'},
    'supplier': {'en': 'Supplier', 'ar': 'المورد', 'fr': 'Fournisseur'},
    'date': {'en': 'Date', 'ar': 'التاريخ', 'fr': 'Date'},
    'subtotal': {'en': 'Subtotal', 'ar': 'المجموع الفرعي', 'fr': 'Sous-total'},
    'taxable': {'en': 'Taxable', 'ar': 'خاضع للضريبة', 'fr': 'Imposable'},
    'tax': {'en': 'Tax', 'ar': 'الضريبة', 'fr': 'Taxe'},
    'total': {'en': 'Total', 'ar': 'الإجمالي', 'fr': 'Total'},
    'return_number': {'en': 'Return #', 'ar': 'رقم المرتجع', 'fr': 'N° Retour'},
    'tax_refunded': {
      'en': 'Tax Refunded',
      'ar': 'ضريبة مستردة',
      'fr': 'Taxe Remboursée',
    },
    'printed_on': {'en': 'Printed on', 'ar': 'طُبع في', 'fr': 'Imprimé le'},
  };

  static String _t(String key, String lang) {
    return _translations[key]?[lang] ?? _translations[key]?['en'] ?? key;
  }

  static pw.Widget _summaryCol(
    String label,
    String value,
    _PdfFonts fonts, {
    bool bold = false,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            font: fonts.regular,
            fontSize: 8,
            color: PdfColors.grey600,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          value,
          style: pw.TextStyle(
            font: bold ? fonts.bold : fonts.regular,
            fontSize: 10,
          ),
        ),
      ],
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
}

class _PdfFonts {
  final pw.Font regular;
  final pw.Font bold;
  const _PdfFonts({required this.regular, required this.bold});
}
