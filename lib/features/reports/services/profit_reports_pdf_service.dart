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
import '../presentation/bloc/profit_reports_bloc.dart';

class ProfitReportsPdfService {
  // ═══════════════════════════════════════════════════════
  // PUBLIC API
  // ═══════════════════════════════════════════════════════

  static Future<void> printOverall({
    required BuildContext context,
    required ProfitReportsData data,
  }) async {
    final pdf = await _buildOverallPdf(context, data);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'ProfitOverall_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> shareOverall({
    required BuildContext context,
    required ProfitReportsData data,
  }) async {
    final pdf = await _buildOverallPdf(context, data);
    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'ProfitOverall_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  static Future<void> printByProduct({
    required BuildContext context,
    required List<ProfitByProductItem> items,
    required ProfitReportsData data,
  }) async {
    final pdf = await _buildByProductPdf(context, items, data);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'ProfitByProduct_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> shareByProduct({
    required BuildContext context,
    required List<ProfitByProductItem> items,
    required ProfitReportsData data,
  }) async {
    final pdf = await _buildByProductPdf(context, items, data);
    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'ProfitByProduct_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  static Future<void> printByCategory({
    required BuildContext context,
    required List<ProfitByCategoryItem> items,
    required ProfitReportsData data,
  }) async {
    final pdf = await _buildByCategoryPdf(context, items, data);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'ProfitByCategory_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> shareByCategory({
    required BuildContext context,
    required List<ProfitByCategoryItem> items,
    required ProfitReportsData data,
  }) async {
    final pdf = await _buildByCategoryPdf(context, items, data);
    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'ProfitByCategory_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  static Future<void> printByCustomer({
    required BuildContext context,
    required List<ProfitByCustomerItem> items,
    required ProfitReportsData data,
  }) async {
    final pdf = await _buildByCustomerPdf(context, items, data);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'ProfitByCustomer_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> shareByCustomer({
    required BuildContext context,
    required List<ProfitByCustomerItem> items,
    required ProfitReportsData data,
  }) async {
    final pdf = await _buildByCustomerPdf(context, items, data);
    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'ProfitByCustomer_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  static Future<void> printByInvoice({
    required BuildContext context,
    required List<ProfitByInvoiceItem> items,
    required ProfitReportsData data,
  }) async {
    final pdf = await _buildByInvoicePdf(context, items, data);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'ProfitByInvoice_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> shareByInvoice({
    required BuildContext context,
    required List<ProfitByInvoiceItem> items,
    required ProfitReportsData data,
  }) async {
    final pdf = await _buildByInvoicePdf(context, items, data);
    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'ProfitByInvoice_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  // ═══════════════════════════════════════════════════════
  // PDF BUILDERS
  // ═══════════════════════════════════════════════════════

  static Future<pw.Document> _buildOverallPdf(
    BuildContext context,
    ProfitReportsData data,
  ) async {
    final lang = context.locale.languageCode;
    final isRtl = lang == 'ar';
    final reportLocation = WarehouseReportContext.maybeOf(context);
    final fonts = await _loadFonts();
    final cs = sl<CurrencyService>();
    await reportLocation?.scope.checkAccess();
    final loadedCompany = await sl<CompanyProfileService>().getProfile();
    final company =
        reportLocation?.decorateCompany(loadedCompany) ?? loadedCompany;
    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final s = data.summary;

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        textDirection: dir,
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => [
          _buildHeader(company, _t('profit_overall', lang), fonts, dir),
          pw.SizedBox(height: 6),
          _buildPeriodLine(data, fonts, lang),
          pw.SizedBox(height: 16),
          // Summary table
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 11),
            cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            headers: [_t('metric', lang), _t('value', lang)],
            data: [
              [_t('revenue', lang), cs.formatCents(s.totalRevenueCents)],
              [_t('cost', lang), cs.formatCents(s.totalCostCents)],
              [_t('gross_profit', lang), cs.formatCents(s.totalProfitCents)],
              [
                _t('profit_margin', lang),
                '${s.profitMarginPercent.toStringAsFixed(1)}%',
              ],
              [
                _t('total_discount', lang),
                cs.formatCents(s.totalDiscountCents),
              ],
              [_t('total_tax', lang), cs.formatCents(s.totalTaxCents)],
              [_t('invoices', lang), '${s.invoiceCount}'],
              [_t('products', lang), '${s.productCount}'],
            ],
          ),
          pw.SizedBox(height: 12),
          _buildFooter(fonts, lang),
        ],
      ),
    );
    return pdf;
  }

  static Future<pw.Document> _buildByProductPdf(
    BuildContext context,
    List<ProfitByProductItem> items,
    ProfitReportsData data,
  ) async {
    final lang = context.locale.languageCode;
    final isRtl = lang == 'ar';
    final reportLocation = WarehouseReportContext.maybeOf(context);
    final fonts = await _loadFonts();
    final cs = sl<CurrencyService>();
    await reportLocation?.scope.checkAccess();
    final loadedCompany = await sl<CompanyProfileService>().getProfile();
    final company =
        reportLocation?.decorateCompany(loadedCompany) ?? loadedCompany;
    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        textDirection: dir,
        pageFormat: PdfPageFormat.a4.landscape,
        build: (ctx) => [
          _buildHeader(company, _t('profit_by_product', lang), fonts, dir),
          pw.SizedBox(height: 6),
          _buildPeriodLine(data, fonts, lang),
          pw.SizedBox(height: 4),
          _buildSummaryLine(data, cs, fonts, lang),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 9),
            cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 8),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            headers: [
              '#',
              _t('product', lang),
              _t('category', lang),
              _t('quantity', lang),
              _t('revenue', lang),
              _t('cost', lang),
              _t('profit', lang),
              _t('margin', lang),
            ],
            data: items.asMap().entries.map((e) {
              final i = e.value;
              return [
                '${e.key + 1}',
                i.productName,
                i.categoryName ?? '-',
                '${i.totalQuantity}',
                cs.formatCents(i.totalRevenueCents),
                cs.formatCents(i.totalCostCents),
                cs.formatCents(i.totalProfitCents),
                '${i.profitMarginPercent.toStringAsFixed(1)}%',
              ];
            }).toList(),
          ),
          pw.SizedBox(height: 12),
          _buildFooter(fonts, lang),
        ],
      ),
    );
    return pdf;
  }

  static Future<pw.Document> _buildByCategoryPdf(
    BuildContext context,
    List<ProfitByCategoryItem> items,
    ProfitReportsData data,
  ) async {
    final lang = context.locale.languageCode;
    final isRtl = lang == 'ar';
    final reportLocation = WarehouseReportContext.maybeOf(context);
    final fonts = await _loadFonts();
    final cs = sl<CurrencyService>();
    await reportLocation?.scope.checkAccess();
    final loadedCompany = await sl<CompanyProfileService>().getProfile();
    final company =
        reportLocation?.decorateCompany(loadedCompany) ?? loadedCompany;
    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        textDirection: dir,
        pageFormat: PdfPageFormat.a4.landscape,
        build: (ctx) => [
          _buildHeader(company, _t('profit_by_category', lang), fonts, dir),
          pw.SizedBox(height: 6),
          _buildPeriodLine(data, fonts, lang),
          pw.SizedBox(height: 4),
          _buildSummaryLine(data, cs, fonts, lang),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 9),
            cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 8),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            headers: [
              '#',
              _t('category', lang),
              _t('products', lang),
              _t('quantity', lang),
              _t('revenue', lang),
              _t('cost', lang),
              _t('profit', lang),
              _t('margin', lang),
            ],
            data: items.asMap().entries.map((e) {
              final i = e.value;
              return [
                '${e.key + 1}',
                i.categoryName,
                '${i.productCount}',
                '${i.totalQuantity}',
                cs.formatCents(i.totalRevenueCents),
                cs.formatCents(i.totalCostCents),
                cs.formatCents(i.totalProfitCents),
                '${i.profitMarginPercent.toStringAsFixed(1)}%',
              ];
            }).toList(),
          ),
          pw.SizedBox(height: 12),
          _buildFooter(fonts, lang),
        ],
      ),
    );
    return pdf;
  }

  static Future<pw.Document> _buildByCustomerPdf(
    BuildContext context,
    List<ProfitByCustomerItem> items,
    ProfitReportsData data,
  ) async {
    final lang = context.locale.languageCode;
    final isRtl = lang == 'ar';
    final reportLocation = WarehouseReportContext.maybeOf(context);
    final fonts = await _loadFonts();
    final cs = sl<CurrencyService>();
    await reportLocation?.scope.checkAccess();
    final loadedCompany = await sl<CompanyProfileService>().getProfile();
    final company =
        reportLocation?.decorateCompany(loadedCompany) ?? loadedCompany;
    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        textDirection: dir,
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => [
          _buildHeader(company, _t('profit_by_customer', lang), fonts, dir),
          pw.SizedBox(height: 6),
          _buildPeriodLine(data, fonts, lang),
          pw.SizedBox(height: 4),
          _buildSummaryLine(data, cs, fonts, lang),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 9),
            cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 8),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            headers: [
              '#',
              _t('customer', lang),
              _t('revenue', lang),
              _t('cost', lang),
              _t('profit', lang),
              _t('margin', lang),
              _t('invoices', lang),
            ],
            data: items.asMap().entries.map((e) {
              final i = e.value;
              return [
                '${e.key + 1}',
                i.customerName,
                cs.formatCents(i.totalRevenueCents),
                cs.formatCents(i.totalCostCents),
                cs.formatCents(i.totalProfitCents),
                '${i.profitMarginPercent.toStringAsFixed(1)}%',
                '${i.invoiceCount}',
              ];
            }).toList(),
          ),
          pw.SizedBox(height: 12),
          _buildFooter(fonts, lang),
        ],
      ),
    );
    return pdf;
  }

  static Future<pw.Document> _buildByInvoicePdf(
    BuildContext context,
    List<ProfitByInvoiceItem> items,
    ProfitReportsData data,
  ) async {
    final lang = context.locale.languageCode;
    final isRtl = lang == 'ar';
    final reportLocation = WarehouseReportContext.maybeOf(context);
    final fonts = await _loadFonts();
    final cs = sl<CurrencyService>();
    await reportLocation?.scope.checkAccess();
    final loadedCompany = await sl<CompanyProfileService>().getProfile();
    final company =
        reportLocation?.decorateCompany(loadedCompany) ?? loadedCompany;
    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        textDirection: dir,
        pageFormat: PdfPageFormat.a4.landscape,
        build: (ctx) => [
          _buildHeader(company, _t('profit_by_invoice', lang), fonts, dir),
          pw.SizedBox(height: 6),
          _buildPeriodLine(data, fonts, lang),
          pw.SizedBox(height: 4),
          _buildSummaryLine(data, cs, fonts, lang),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 9),
            cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 8),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            headers: [
              '#',
              _t('invoice_number', lang),
              _t('customer', lang),
              _t('revenue', lang),
              _t('cost', lang),
              _t('profit', lang),
              _t('margin', lang),
              _t('date', lang),
            ],
            data: items.asMap().entries.map((e) {
              final i = e.value;
              return [
                '${e.key + 1}',
                i.invoiceNumber,
                i.customerName ?? '-',
                cs.formatCents(i.revenueCents),
                cs.formatCents(i.costCents),
                cs.formatCents(i.profitCents),
                '${i.profitMarginPercent.toStringAsFixed(1)}%',
                DateFormat('dd/MM/yyyy').format(i.saleDate),
              ];
            }).toList(),
          ),
          pw.SizedBox(height: 12),
          _buildFooter(fonts, lang),
        ],
      ),
    );
    return pdf;
  }

  // ═══════════════════════════════════════════════════════
  // SHARED HELPERS
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

  static pw.Widget _buildPeriodLine(
    ProfitReportsData data,
    _PdfFonts fonts,
    String lang,
  ) {
    return pw.Text(
      '${_t('period', lang)}: ${DateFormat('dd/MM/yyyy').format(data.dateRange.startDate)} — ${DateFormat('dd/MM/yyyy').format(data.dateRange.endDate)}',
      style: pw.TextStyle(font: fonts.regular, fontSize: 10),
    );
  }

  static pw.Widget _buildSummaryLine(
    ProfitReportsData data,
    CurrencyService cs,
    _PdfFonts fonts,
    String lang,
  ) {
    final s = data.summary;
    return pw.Text(
      '${_t('revenue', lang)}: ${cs.formatCents(s.totalRevenueCents)}  |  ${_t('cost', lang)}: ${cs.formatCents(s.totalCostCents)}  |  ${_t('profit', lang)}: ${cs.formatCents(s.totalProfitCents)}  |  ${_t('margin', lang)}: ${s.profitMarginPercent.toStringAsFixed(1)}%',
      style: pw.TextStyle(
        font: fonts.regular,
        fontSize: 9,
        color: PdfColors.grey700,
      ),
    );
  }

  static pw.Widget _buildFooter(_PdfFonts fonts, String lang) {
    return pw.Column(
      children: [
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
  // 3-LANGUAGE TRANSLATIONS
  // ═══════════════════════════════════════════════════════

  static const _translations = {
    'period': {'en': 'Period', 'ar': 'الفترة', 'fr': 'Période'},
    'metric': {'en': 'Metric', 'ar': 'المقياس', 'fr': 'Métrique'},
    'value': {'en': 'Value', 'ar': 'القيمة', 'fr': 'Valeur'},
    'revenue': {
      'en': 'Revenue',
      'ar': 'الإيرادات',
      'fr': 'Chiffre d\'Affaires',
    },
    'cost': {'en': 'Cost (COGS)', 'ar': 'التكلفة', 'fr': 'Coût (CMV)'},
    'gross_profit': {
      'en': 'Gross Profit',
      'ar': 'الربح الإجمالي',
      'fr': 'Bénéfice Brut',
    },
    'profit': {'en': 'Profit', 'ar': 'الربح', 'fr': 'Bénéfice'},
    'profit_margin': {
      'en': 'Profit Margin',
      'ar': 'هامش الربح',
      'fr': 'Marge Bénéficiaire',
    },
    'margin': {'en': 'Margin %', 'ar': 'الهامش %', 'fr': 'Marge %'},
    'total_discount': {
      'en': 'Total Discount',
      'ar': 'إجمالي الخصم',
      'fr': 'Remise Totale',
    },
    'total_tax': {
      'en': 'Total Tax',
      'ar': 'إجمالي الضريبة',
      'fr': 'Taxe Totale',
    },
    'invoices': {'en': 'Invoices', 'ar': 'الفواتير', 'fr': 'Factures'},
    'products': {'en': 'Products', 'ar': 'المنتجات', 'fr': 'Produits'},
    'invoice_number': {
      'en': 'Invoice #',
      'ar': 'رقم الفاتورة',
      'fr': 'Facture #',
    },
    'customer': {'en': 'Customer', 'ar': 'العميل', 'fr': 'Client'},
    'date': {'en': 'Date', 'ar': 'التاريخ', 'fr': 'Date'},
    'product': {'en': 'Product', 'ar': 'المنتج', 'fr': 'Produit'},
    'category': {'en': 'Category', 'ar': 'التصنيف', 'fr': 'Catégorie'},
    'quantity': {'en': 'Qty', 'ar': 'الكمية', 'fr': 'Qté'},
    'printed_on': {'en': 'Printed on', 'ar': 'طُبع في', 'fr': 'Imprimé le'},
    'profit_overall': {
      'en': 'Sales & Profit Report',
      'ar': 'تقرير المبيعات والأرباح',
      'fr': 'Rapport Ventes & Bénéfices',
    },
    'profit_by_product': {
      'en': 'Profit by Product',
      'ar': 'الأرباح حسب الصنف',
      'fr': 'Bénéfice par Produit',
    },
    'profit_by_category': {
      'en': 'Profit by Category',
      'ar': 'الأرباح حسب التصنيف',
      'fr': 'Bénéfice par Catégorie',
    },
    'profit_by_customer': {
      'en': 'Profit by Customer',
      'ar': 'الأرباح حسب العميل',
      'fr': 'Bénéfice par Client',
    },
    'profit_by_invoice': {
      'en': 'Profit by Invoice',
      'ar': 'الأرباح حسب الفاتورة',
      'fr': 'Bénéfice par Facture',
    },
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
