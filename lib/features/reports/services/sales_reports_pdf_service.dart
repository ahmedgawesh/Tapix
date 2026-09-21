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
import '../presentation/bloc/sales_reports_bloc.dart';

class SalesReportsPdfService {
  // ═══════════════════════════════════════════════════════
  // PUBLIC API — Print / Share for each report type
  // ═══════════════════════════════════════════════════════

  /// All Sales / Sales by Period / Payment method reports
  static Future<void> printInvoiceList({
    required BuildContext context,
    required String title,
    required List<SaleInvoiceItem> invoices,
    required SalesReportsData data,
  }) async {
    final pdf = await _buildInvoiceListPdf(context, title, invoices, data);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: '${title}_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> shareInvoiceList({
    required BuildContext context,
    required String title,
    required List<SaleInvoiceItem> invoices,
    required SalesReportsData data,
  }) async {
    final pdf = await _buildInvoiceListPdf(context, title, invoices, data);
    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename: '${title}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  /// Sales by Product
  static Future<void> printByProduct({
    required BuildContext context,
    required List<SalesByProductItem> items,
    required SalesReportsData data,
  }) async {
    final pdf = await _buildByProductPdf(context, items, data);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'SalesByProduct_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> shareByProduct({
    required BuildContext context,
    required List<SalesByProductItem> items,
    required SalesReportsData data,
  }) async {
    final pdf = await _buildByProductPdf(context, items, data);
    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'SalesByProduct_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  /// Sales by Category
  static Future<void> printByCategory({
    required BuildContext context,
    required List<SalesByCategoryItem> items,
    required SalesReportsData data,
  }) async {
    final pdf = await _buildByCategoryPdf(context, items, data);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'SalesByCategory_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> shareByCategory({
    required BuildContext context,
    required List<SalesByCategoryItem> items,
    required SalesReportsData data,
  }) async {
    final pdf = await _buildByCategoryPdf(context, items, data);
    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'SalesByCategory_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  /// Sales by Customer
  static Future<void> printByCustomer({
    required BuildContext context,
    required List<SalesByCustomerItem> items,
    required SalesReportsData data,
  }) async {
    final pdf = await _buildByCustomerPdf(context, items, data);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'SalesByCustomer_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> shareByCustomer({
    required BuildContext context,
    required List<SalesByCustomerItem> items,
    required SalesReportsData data,
  }) async {
    final pdf = await _buildByCustomerPdf(context, items, data);
    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'SalesByCustomer_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  /// Cancelled Invoices
  static Future<void> printCancelled({
    required BuildContext context,
    required List<CancelledInvoiceItem> items,
    required SalesReportsData data,
  }) async {
    final pdf = await _buildCancelledPdf(context, items, data);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name:
          'CancelledInvoices_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> shareCancelled({
    required BuildContext context,
    required List<CancelledInvoiceItem> items,
    required SalesReportsData data,
  }) async {
    final pdf = await _buildCancelledPdf(context, items, data);
    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'CancelledInvoices_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  /// Tax by Product
  static Future<void> printTaxByProduct({
    required BuildContext context,
    required List<TaxByProductItem> items,
    required SalesReportsData data,
  }) async {
    final pdf = await _buildTaxByProductPdf(context, items, data);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'TaxByProduct_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> shareTaxByProduct({
    required BuildContext context,
    required List<TaxByProductItem> items,
    required SalesReportsData data,
  }) async {
    final pdf = await _buildTaxByProductPdf(context, items, data);
    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'TaxByProduct_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  /// Tax by Customer
  static Future<void> printTaxByCustomer({
    required BuildContext context,
    required List<TaxByCustomerItem> items,
    required SalesReportsData data,
  }) async {
    final pdf = await _buildTaxByCustomerPdf(context, items, data);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'TaxByCustomer_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> shareTaxByCustomer({
    required BuildContext context,
    required List<TaxByCustomerItem> items,
    required SalesReportsData data,
  }) async {
    final pdf = await _buildTaxByCustomerPdf(context, items, data);
    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'TaxByCustomer_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  // ═══════════════════════════════════════════════════════
  // PDF BUILDERS
  // ═══════════════════════════════════════════════════════

  static Future<pw.Document> _buildInvoiceListPdf(
    BuildContext context,
    String title,
    List<SaleInvoiceItem> invoices,
    SalesReportsData data,
  ) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final reportLocation = WarehouseReportContext.maybeOf(context);
    await reportLocation?.scope.checkAccess();
    final loadedCompany = await sl<CompanyProfileService>().getProfile();
    final company =
        reportLocation?.decorateCompany(loadedCompany) ?? loadedCompany;
    final fonts = await _loadFonts();
    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final lang = locale.languageCode;

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        textDirection: dir,
        build: (pw.Context ctx) => [
          _buildHeader(company, title, fonts, dir),
          pw.SizedBox(height: 8),
          _buildPeriodLine(data, fonts, lang),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                '${_t('total_sales', lang)}: ${cs.formatCents(data.summary.totalSalesCents)}',
                style: pw.TextStyle(font: fonts.bold, fontSize: 11),
              ),
              pw.Text(
                '${_t('invoices', lang)}: ${invoices.length}',
                style: pw.TextStyle(font: fonts.bold, fontSize: 11),
              ),
              pw.Text(
                '${_t('total_discount', lang)}: ${cs.formatCents(data.summary.totalDiscountCents)}',
                style: pw.TextStyle(font: fonts.regular, fontSize: 10),
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          if (invoices.isNotEmpty)
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 7),
              cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 7),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
              headers: [
                '#',
                _t('invoice_number', lang),
                _t('customer', lang),
                _t('cashier', lang),
                _t('subtotal', lang),
                _t('discount', lang),
                _t('tax', lang),
                _t('total', lang),
                _t('paid', lang),
                _t('payment_method', lang),
                _t('date', lang),
              ],
              data: invoices.asMap().entries.map((e) {
                final i = e.value;
                return [
                  '${e.key + 1}',
                  i.invoiceNumber,
                  i.customerName ?? '-',
                  _cashierLabel(i, lang),
                  cs.formatCents(i.subtotalCents),
                  cs.formatCents(i.discountCents),
                  cs.formatCents(i.taxCents),
                  cs.formatCents(i.totalCents),
                  cs.formatCents(i.paidAmountCents),
                  _paymentLabel(i.paymentMethod, lang),
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

  static Future<pw.Document> _buildByProductPdf(
    BuildContext context,
    List<SalesByProductItem> items,
    SalesReportsData data,
  ) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final reportLocation = WarehouseReportContext.maybeOf(context);
    await reportLocation?.scope.checkAccess();
    final loadedCompany = await sl<CompanyProfileService>().getProfile();
    final company =
        reportLocation?.decorateCompany(loadedCompany) ?? loadedCompany;
    final fonts = await _loadFonts();
    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final lang = locale.languageCode;

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: dir,
        build: (pw.Context ctx) => [
          _buildHeader(company, _t('sales_by_product', lang), fonts, dir),
          pw.SizedBox(height: 8),
          _buildPeriodLine(data, fonts, lang),
          pw.SizedBox(height: 4),
          pw.Text(
            '${_t('total_sales', lang)}: ${cs.formatCents(data.summary.totalSalesCents)}  |  ${_t('products', lang)}: ${items.length}',
            style: pw.TextStyle(font: fonts.bold, fontSize: 10),
          ),
          pw.SizedBox(height: 12),
          if (items.isNotEmpty)
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 8),
              cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 8),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
              headers: [
                '#',
                _t('product', lang),
                _t('category', lang),
                _t('quantity', lang),
                _t('total_sales', lang),
                _t('discount', lang),
                _t('tax', lang),
                _t('invoices', lang),
              ],
              data: items.asMap().entries.map((e) {
                final p = e.value;
                return [
                  '${e.key + 1}',
                  p.productName,
                  p.categoryName ?? '-',
                  '${p.totalQuantity}',
                  cs.formatCents(p.totalSalesCents),
                  cs.formatCents(p.totalDiscountCents),
                  cs.formatCents(p.totalTaxCents),
                  '${p.invoiceCount}',
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
    List<SalesByCategoryItem> items,
    SalesReportsData data,
  ) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final reportLocation = WarehouseReportContext.maybeOf(context);
    await reportLocation?.scope.checkAccess();
    final loadedCompany = await sl<CompanyProfileService>().getProfile();
    final company =
        reportLocation?.decorateCompany(loadedCompany) ?? loadedCompany;
    final fonts = await _loadFonts();
    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final lang = locale.languageCode;

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: dir,
        build: (pw.Context ctx) => [
          _buildHeader(company, _t('sales_by_category', lang), fonts, dir),
          pw.SizedBox(height: 8),
          _buildPeriodLine(data, fonts, lang),
          pw.SizedBox(height: 4),
          pw.Text(
            '${_t('total_sales', lang)}: ${cs.formatCents(data.summary.totalSalesCents)}  |  ${_t('categories', lang)}: ${items.length}',
            style: pw.TextStyle(font: fonts.bold, fontSize: 10),
          ),
          pw.SizedBox(height: 12),
          if (items.isNotEmpty)
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 8),
              cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 8),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
              headers: [
                '#',
                _t('category', lang),
                _t('products', lang),
                _t('quantity', lang),
                _t('total_sales', lang),
                _t('discount', lang),
                _t('tax', lang),
                _t('invoices', lang),
              ],
              data: items.asMap().entries.map((e) {
                final c = e.value;
                return [
                  '${e.key + 1}',
                  c.categoryName,
                  '${c.productCount}',
                  '${c.totalQuantity}',
                  cs.formatCents(c.totalSalesCents),
                  cs.formatCents(c.totalDiscountCents),
                  cs.formatCents(c.totalTaxCents),
                  '${c.invoiceCount}',
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
    List<SalesByCustomerItem> items,
    SalesReportsData data,
  ) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final reportLocation = WarehouseReportContext.maybeOf(context);
    await reportLocation?.scope.checkAccess();
    final loadedCompany = await sl<CompanyProfileService>().getProfile();
    final company =
        reportLocation?.decorateCompany(loadedCompany) ?? loadedCompany;
    final fonts = await _loadFonts();
    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final lang = locale.languageCode;

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: dir,
        build: (pw.Context ctx) => [
          _buildHeader(company, _t('sales_by_customer', lang), fonts, dir),
          pw.SizedBox(height: 8),
          _buildPeriodLine(data, fonts, lang),
          pw.SizedBox(height: 4),
          pw.Text(
            '${_t('total_sales', lang)}: ${cs.formatCents(data.summary.totalSalesCents)}  |  ${_t('customers', lang)}: ${items.length}',
            style: pw.TextStyle(font: fonts.bold, fontSize: 10),
          ),
          pw.SizedBox(height: 12),
          if (items.isNotEmpty)
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 8),
              cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 8),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
              headers: [
                '#',
                _t('customer', lang),
                _t('total_sales', lang),
                _t('discount', lang),
                _t('tax', lang),
                _t('invoices', lang),
                _t('quantity', lang),
                _t('last_sale', lang),
              ],
              data: items.asMap().entries.map((e) {
                final c = e.value;
                return [
                  '${e.key + 1}',
                  c.customerName,
                  cs.formatCents(c.totalSalesCents),
                  cs.formatCents(c.totalDiscountCents),
                  cs.formatCents(c.totalTaxCents),
                  '${c.invoiceCount}',
                  '${c.totalQuantity}',
                  c.lastSaleDate != null
                      ? DateFormat('dd/MM/yyyy').format(c.lastSaleDate!)
                      : '-',
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

  static Future<pw.Document> _buildCancelledPdf(
    BuildContext context,
    List<CancelledInvoiceItem> items,
    SalesReportsData data,
  ) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final reportLocation = WarehouseReportContext.maybeOf(context);
    await reportLocation?.scope.checkAccess();
    final loadedCompany = await sl<CompanyProfileService>().getProfile();
    final company =
        reportLocation?.decorateCompany(loadedCompany) ?? loadedCompany;
    final fonts = await _loadFonts();
    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final lang = locale.languageCode;

    final totalCancelled = items.fold<int>(0, (s, i) => s + i.totalCents);

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: dir,
        build: (pw.Context ctx) => [
          _buildHeader(company, _t('cancelled_invoices', lang), fonts, dir),
          pw.SizedBox(height: 8),
          _buildPeriodLine(data, fonts, lang),
          pw.SizedBox(height: 4),
          pw.Text(
            '${_t('total', lang)}: ${cs.formatCents(totalCancelled)}  |  ${_t('invoices', lang)}: ${items.length}',
            style: pw.TextStyle(font: fonts.bold, fontSize: 10),
          ),
          pw.SizedBox(height: 12),
          if (items.isNotEmpty)
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 8),
              cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 8),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
              headers: [
                '#',
                _t('invoice_number', lang),
                _t('customer', lang),
                _t('total', lang),
                _t('date', lang),
                _t('notes', lang),
              ],
              data: items.asMap().entries.map((e) {
                final i = e.value;
                return [
                  '${e.key + 1}',
                  i.invoiceNumber,
                  i.customerName ?? '-',
                  cs.formatCents(i.totalCents),
                  DateFormat('dd/MM/yyyy').format(i.saleDate),
                  i.notes ?? '-',
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

  static Future<pw.Document> _buildTaxByProductPdf(
    BuildContext context,
    List<TaxByProductItem> items,
    SalesReportsData data,
  ) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final reportLocation = WarehouseReportContext.maybeOf(context);
    await reportLocation?.scope.checkAccess();
    final loadedCompany = await sl<CompanyProfileService>().getProfile();
    final company =
        reportLocation?.decorateCompany(loadedCompany) ?? loadedCompany;
    final fonts = await _loadFonts();
    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final lang = locale.languageCode;

    final totalTax = items.fold<int>(0, (s, i) => s + i.totalTaxCents);

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: dir,
        build: (pw.Context ctx) => [
          _buildHeader(company, _t('tax_by_product', lang), fonts, dir),
          pw.SizedBox(height: 8),
          _buildPeriodLine(data, fonts, lang),
          pw.SizedBox(height: 4),
          pw.Text(
            '${_t('total_tax', lang)}: ${cs.formatCents(totalTax)}  |  ${_t('products', lang)}: ${items.length}',
            style: pw.TextStyle(font: fonts.bold, fontSize: 10),
          ),
          pw.SizedBox(height: 12),
          if (items.isNotEmpty)
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 8),
              cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 8),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
              headers: [
                '#',
                _t('product', lang),
                _t('total_sales', lang),
                _t('tax_rate', lang),
                _t('total_tax', lang),
                _t('quantity', lang),
              ],
              data: items.asMap().entries.map((e) {
                final t = e.value;
                return [
                  '${e.key + 1}',
                  t.productName,
                  cs.formatCents(t.totalSalesCents),
                  '${(t.taxRateBps / 100).toStringAsFixed(1)}%',
                  cs.formatCents(t.totalTaxCents),
                  '${t.totalQuantity}',
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

  static Future<pw.Document> _buildTaxByCustomerPdf(
    BuildContext context,
    List<TaxByCustomerItem> items,
    SalesReportsData data,
  ) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final reportLocation = WarehouseReportContext.maybeOf(context);
    await reportLocation?.scope.checkAccess();
    final loadedCompany = await sl<CompanyProfileService>().getProfile();
    final company =
        reportLocation?.decorateCompany(loadedCompany) ?? loadedCompany;
    final fonts = await _loadFonts();
    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final lang = locale.languageCode;

    final totalTax = items.fold<int>(0, (s, i) => s + i.totalTaxCents);

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: dir,
        build: (pw.Context ctx) => [
          _buildHeader(company, _t('tax_by_customer', lang), fonts, dir),
          pw.SizedBox(height: 8),
          _buildPeriodLine(data, fonts, lang),
          pw.SizedBox(height: 4),
          pw.Text(
            '${_t('total_tax', lang)}: ${cs.formatCents(totalTax)}  |  ${_t('customers', lang)}: ${items.length}',
            style: pw.TextStyle(font: fonts.bold, fontSize: 10),
          ),
          pw.SizedBox(height: 12),
          if (items.isNotEmpty)
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 8),
              cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 8),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
              headers: [
                '#',
                _t('customer', lang),
                _t('total_sales', lang),
                _t('total_tax', lang),
                _t('invoices', lang),
              ],
              data: items.asMap().entries.map((e) {
                final t = e.value;
                return [
                  '${e.key + 1}',
                  t.customerName,
                  cs.formatCents(t.totalSalesCents),
                  cs.formatCents(t.totalTaxCents),
                  '${t.invoiceCount}',
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
    SalesReportsData data,
    _PdfFonts fonts,
    String lang,
  ) {
    return pw.Text(
      '${_t('period', lang)}: ${DateFormat('dd/MM/yyyy').format(data.dateRange.startDate)} — ${DateFormat('dd/MM/yyyy').format(data.dateRange.endDate)}',
      style: pw.TextStyle(font: fonts.regular, fontSize: 10),
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

  static String _cashierLabel(SaleInvoiceItem invoice, String lang) {
    final parts = <String>[
      if (invoice.cashierName?.trim().isNotEmpty ?? false)
        invoice.cashierName!.trim(),
      if (invoice.cashierShiftNumber?.trim().isNotEmpty ?? false)
        '${_t('shift', lang)}: ${invoice.cashierShiftNumber!.trim()}',
    ];
    return parts.isEmpty ? '-' : parts.join('\n');
  }

  static String _paymentLabel(String method, String lang) {
    switch (method) {
      case 'cash':
        return _t('payment_cash', lang);
      case 'credit':
        return _t('payment_credit', lang);
      case 'card':
        return _t('payment_card', lang);
      case 'cheque':
        return _t('payment_cheque', lang);
      default:
        return method;
    }
  }

  // ═══════════════════════════════════════════════════════
  // FONTS
  // ═══════════════════════════════════════════════════════

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
    'total_tax': {
      'en': 'Total Tax',
      'ar': 'إجمالي الضريبة',
      'fr': 'Taxe Totale',
    },
    'total': {'en': 'Total', 'ar': 'الإجمالي', 'fr': 'Total'},
    'invoices': {'en': 'Invoices', 'ar': 'الفواتير', 'fr': 'Factures'},
    'products': {'en': 'Products', 'ar': 'المنتجات', 'fr': 'Produits'},
    'categories': {'en': 'Categories', 'ar': 'التصنيفات', 'fr': 'Catégories'},
    'customers': {'en': 'Customers', 'ar': 'العملاء', 'fr': 'Clients'},
    'invoice_number': {
      'en': 'Invoice #',
      'ar': 'رقم الفاتورة',
      'fr': 'Facture #',
    },
    'customer': {'en': 'Customer', 'ar': 'العميل', 'fr': 'Client'},
    'cashier': {
      'en': 'Cashier / Shift',
      'ar': 'الكاشير / الوردية',
      'fr': 'Caissier / Caisse',
    },
    'shift': {'en': 'Shift', 'ar': 'وردية', 'fr': 'Caisse'},
    'subtotal': {'en': 'Subtotal', 'ar': 'المجموع الفرعي', 'fr': 'Sous-total'},
    'discount': {'en': 'Discount', 'ar': 'الخصم', 'fr': 'Remise'},
    'tax': {'en': 'Tax', 'ar': 'الضريبة', 'fr': 'Taxe'},
    'paid': {'en': 'Paid', 'ar': 'المدفوع', 'fr': 'Payé'},
    'payment_method': {'en': 'Payment', 'ar': 'الدفع', 'fr': 'Paiement'},
    'date': {'en': 'Date', 'ar': 'التاريخ', 'fr': 'Date'},
    'product': {'en': 'Product', 'ar': 'المنتج', 'fr': 'Produit'},
    'category': {'en': 'Category', 'ar': 'التصنيف', 'fr': 'Catégorie'},
    'quantity': {'en': 'Qty', 'ar': 'الكمية', 'fr': 'Qté'},
    'last_sale': {'en': 'Last Sale', 'ar': 'آخر بيع', 'fr': 'Dernière Vente'},
    'notes': {'en': 'Notes', 'ar': 'ملاحظات', 'fr': 'Notes'},
    'tax_rate': {'en': 'Tax Rate', 'ar': 'نسبة الضريبة', 'fr': 'Taux'},
    'printed_on': {'en': 'Printed on', 'ar': 'طُبع في', 'fr': 'Imprimé le'},
    'payment_cash': {'en': 'Cash', 'ar': 'نقد', 'fr': 'Espèces'},
    'payment_credit': {'en': 'Credit', 'ar': 'آجل', 'fr': 'Crédit'},
    'payment_card': {'en': 'Card', 'ar': 'بطاقة', 'fr': 'Carte'},
    'payment_cheque': {'en': 'Cheque', 'ar': 'شيك', 'fr': 'Chèque'},
    'payment_mixed': {'en': 'Mixed', 'ar': 'مختلط', 'fr': 'Mixte'},
    'sales_by_product': {
      'en': 'Sales by Product',
      'ar': 'المبيعات حسب الصنف',
      'fr': 'Ventes par Produit',
    },
    'sales_by_category': {
      'en': 'Sales by Category',
      'ar': 'المبيعات حسب التصنيف',
      'fr': 'Ventes par Catégorie',
    },
    'sales_by_customer': {
      'en': 'Sales by Customer',
      'ar': 'المبيعات حسب العميل',
      'fr': 'Ventes par Client',
    },
    'cancelled_invoices': {
      'en': 'Cancelled Invoices',
      'ar': 'فواتير ملغاة',
      'fr': 'Factures Annulées',
    },
    'tax_by_product': {
      'en': 'Tax by Product',
      'ar': 'الضرائب حسب الصنف',
      'fr': 'Taxes par Produit',
    },
    'tax_by_customer': {
      'en': 'Tax by Customer',
      'ar': 'الضرائب حسب العميل',
      'fr': 'Taxes par Client',
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
