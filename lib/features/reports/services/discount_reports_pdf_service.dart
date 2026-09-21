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
import '../presentation/bloc/discount_reports_bloc.dart';

class DiscountReportsPdfService {
  // ═══════════════════════════════════════════════════════
  // PUBLIC API
  // ═══════════════════════════════════════════════════════

  static Future<void> printByProduct({
    required BuildContext context,
    required List<DiscountByProductItem> items,
    required DiscountReportsData data,
  }) async {
    final pdf = await _buildByProductPdf(context, items, data);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name:
          'DiscountByProduct_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> shareByProduct({
    required BuildContext context,
    required List<DiscountByProductItem> items,
    required DiscountReportsData data,
  }) async {
    final pdf = await _buildByProductPdf(context, items, data);
    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'DiscountByProduct_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  static Future<void> printByCategory({
    required BuildContext context,
    required List<DiscountByCategoryItem> items,
    required DiscountReportsData data,
  }) async {
    final pdf = await _buildByCategoryPdf(context, items, data);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name:
          'DiscountByCategory_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> shareByCategory({
    required BuildContext context,
    required List<DiscountByCategoryItem> items,
    required DiscountReportsData data,
  }) async {
    final pdf = await _buildByCategoryPdf(context, items, data);
    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'DiscountByCategory_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  static Future<void> printByCustomer({
    required BuildContext context,
    required List<DiscountByCustomerItem> items,
    required DiscountReportsData data,
  }) async {
    final pdf = await _buildByCustomerPdf(context, items, data);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name:
          'DiscountByCustomer_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> shareByCustomer({
    required BuildContext context,
    required List<DiscountByCustomerItem> items,
    required DiscountReportsData data,
  }) async {
    final pdf = await _buildByCustomerPdf(context, items, data);
    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'DiscountByCustomer_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  static Future<void> printByInvoice({
    required BuildContext context,
    required List<DiscountByInvoiceItem> items,
    required DiscountReportsData data,
  }) async {
    final pdf = await _buildByInvoicePdf(context, items, data);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name:
          'DiscountByInvoice_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> shareByInvoice({
    required BuildContext context,
    required List<DiscountByInvoiceItem> items,
    required DiscountReportsData data,
  }) async {
    final pdf = await _buildByInvoicePdf(context, items, data);
    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'DiscountByInvoice_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  // ═══════════════════════════════════════════════════════
  // PDF BUILDERS
  // ═══════════════════════════════════════════════════════

  static Future<pw.Document> _buildByProductPdf(
    BuildContext context,
    List<DiscountByProductItem> items,
    DiscountReportsData data,
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
          _buildHeader(company, _t('discount_by_product', lang), fonts, dir),
          pw.SizedBox(height: 6),
          _buildPeriodLine(data, fonts, lang),
          pw.SizedBox(height: 4),
          _buildSummaryLine(data, cs, fonts, lang),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 9),
            cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 8),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellAlignments: {
              0: pw.Alignment.center,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
              6: pw.Alignment.centerRight,
              7: pw.Alignment.centerRight,
            },
            headers: [
              '#',
              _t('product', lang),
              _t('category', lang),
              _t('quantity', lang),
              _t('total_sales', lang),
              _t('discount', lang),
              _t('discount_pct', lang),
              _t('invoices', lang),
            ],
            data: items.asMap().entries.map((e) {
              final i = e.value;
              return [
                '${e.key + 1}',
                i.productName,
                i.categoryName ?? '-',
                '${i.totalQuantity}',
                cs.formatCents(i.totalSalesCents),
                cs.formatCents(i.totalDiscountCents),
                '${i.discountPercent.toStringAsFixed(1)}%',
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

  static Future<pw.Document> _buildByCategoryPdf(
    BuildContext context,
    List<DiscountByCategoryItem> items,
    DiscountReportsData data,
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
          _buildHeader(company, _t('discount_by_category', lang), fonts, dir),
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
              _t('total_sales', lang),
              _t('discount', lang),
              _t('discount_pct', lang),
              _t('invoices', lang),
            ],
            data: items.asMap().entries.map((e) {
              final i = e.value;
              return [
                '${e.key + 1}',
                i.categoryName,
                '${i.productCount}',
                '${i.totalQuantity}',
                cs.formatCents(i.totalSalesCents),
                cs.formatCents(i.totalDiscountCents),
                '${i.discountPercent.toStringAsFixed(1)}%',
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

  static Future<pw.Document> _buildByCustomerPdf(
    BuildContext context,
    List<DiscountByCustomerItem> items,
    DiscountReportsData data,
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
          _buildHeader(company, _t('discount_by_customer', lang), fonts, dir),
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
              _t('total_sales', lang),
              _t('discount', lang),
              _t('discount_pct', lang),
              _t('invoices', lang),
            ],
            data: items.asMap().entries.map((e) {
              final i = e.value;
              return [
                '${e.key + 1}',
                i.customerName,
                cs.formatCents(i.totalSalesCents),
                cs.formatCents(i.totalDiscountCents),
                '${i.discountPercent.toStringAsFixed(1)}%',
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
    List<DiscountByInvoiceItem> items,
    DiscountReportsData data,
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
          _buildHeader(company, _t('discount_by_invoice', lang), fonts, dir),
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
              _t('subtotal', lang),
              _t('discount', lang),
              _t('discount_pct', lang),
              _t('total', lang),
              _t('date', lang),
            ],
            data: items.asMap().entries.map((e) {
              final i = e.value;
              return [
                '${e.key + 1}',
                i.invoiceNumber,
                i.customerName ?? '-',
                cs.formatCents(i.subtotalCents),
                cs.formatCents(i.discountCents),
                '${i.discountPercent.toStringAsFixed(1)}%',
                cs.formatCents(i.totalCents),
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
    DiscountReportsData data,
    _PdfFonts fonts,
    String lang,
  ) {
    return pw.Text(
      '${_t('period', lang)}: ${DateFormat('dd/MM/yyyy').format(data.dateRange.startDate)} — ${DateFormat('dd/MM/yyyy').format(data.dateRange.endDate)}',
      style: pw.TextStyle(font: fonts.regular, fontSize: 10),
    );
  }

  static pw.Widget _buildSummaryLine(
    DiscountReportsData data,
    CurrencyService cs,
    _PdfFonts fonts,
    String lang,
  ) {
    final s = data.summary;
    return pw.Text(
      '${_t('total_discount', lang)}: ${cs.formatCents(s.totalDiscountCents)}  |  ${_t('discounted_invoices', lang)}: ${s.discountedInvoiceCount}  |  ${_t('avg_discount', lang)}: ${s.averageDiscountPercent.toStringAsFixed(1)}%',
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
    'total_sales': {
      'en': 'Total Sales',
      'ar': 'إجمالي المبيعات',
      'fr': 'Total des Ventes',
    },
    'total_discount': {
      'en': 'Total Discount',
      'ar': 'إجمالي الخصم',
      'fr': 'Remise Totale',
    },
    'discount': {'en': 'Discount', 'ar': 'الخصم', 'fr': 'Remise'},
    'discount_pct': {'en': 'Discount %', 'ar': 'نسبة الخصم', 'fr': 'Remise %'},
    'discounted_invoices': {
      'en': 'Discounted Invoices',
      'ar': 'فواتير بخصم',
      'fr': 'Factures avec Remise',
    },
    'avg_discount': {
      'en': 'Avg Discount',
      'ar': 'متوسط الخصم',
      'fr': 'Remise Moy.',
    },
    'total': {'en': 'Total', 'ar': 'الإجمالي', 'fr': 'Total'},
    'invoices': {'en': 'Invoices', 'ar': 'الفواتير', 'fr': 'Factures'},
    'products': {'en': 'Products', 'ar': 'المنتجات', 'fr': 'Produits'},
    'invoice_number': {
      'en': 'Invoice #',
      'ar': 'رقم الفاتورة',
      'fr': 'Facture #',
    },
    'customer': {'en': 'Customer', 'ar': 'العميل', 'fr': 'Client'},
    'subtotal': {'en': 'Subtotal', 'ar': 'المجموع الفرعي', 'fr': 'Sous-total'},
    'date': {'en': 'Date', 'ar': 'التاريخ', 'fr': 'Date'},
    'product': {'en': 'Product', 'ar': 'المنتج', 'fr': 'Produit'},
    'category': {'en': 'Category', 'ar': 'التصنيف', 'fr': 'Catégorie'},
    'quantity': {'en': 'Qty', 'ar': 'الكمية', 'fr': 'Qté'},
    'printed_on': {'en': 'Printed on', 'ar': 'طُبع في', 'fr': 'Imprimé le'},
    'discount_by_product': {
      'en': 'Discounts by Product',
      'ar': 'الخصومات حسب الصنف',
      'fr': 'Remises par Produit',
    },
    'discount_by_category': {
      'en': 'Discounts by Category',
      'ar': 'الخصومات حسب التصنيف',
      'fr': 'Remises par Catégorie',
    },
    'discount_by_customer': {
      'en': 'Discounts by Customer',
      'ar': 'الخصومات حسب العميل',
      'fr': 'Remises par Client',
    },
    'discount_by_invoice': {
      'en': 'Discounts by Invoice',
      'ar': 'الخصومات حسب الفاتورة',
      'fr': 'Remises par Facture',
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
