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
import '../presentation/bloc/purchase_reports_bloc.dart';

class PurchaseReportsPdfService {
  // ═══════════════════════════════════════════════════════
  // PUBLIC API — Print / Share for each report type
  // ═══════════════════════════════════════════════════════

  /// All Purchases / Payment method reports
  static Future<void> printInvoiceList({
    required BuildContext context,
    required String title,
    required List<PurchaseInvoiceItem> invoices,
    required PurchaseReportsData data,
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
    required List<PurchaseInvoiceItem> invoices,
    required PurchaseReportsData data,
  }) async {
    final pdf = await _buildInvoiceListPdf(context, title, invoices, data);
    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename: '${title}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  /// Purchases by Product
  static Future<void> printByProduct({
    required BuildContext context,
    required List<PurchasesByProductItem> items,
    required PurchaseReportsData data,
  }) async {
    final pdf = await _buildByProductPdf(context, items, data);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name:
          'PurchasesByProduct_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> shareByProduct({
    required BuildContext context,
    required List<PurchasesByProductItem> items,
    required PurchaseReportsData data,
  }) async {
    final pdf = await _buildByProductPdf(context, items, data);
    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'PurchasesByProduct_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  /// Purchases by Category
  static Future<void> printByCategory({
    required BuildContext context,
    required List<PurchasesByCategoryItem> items,
    required PurchaseReportsData data,
  }) async {
    final pdf = await _buildByCategoryPdf(context, items, data);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name:
          'PurchasesByCategory_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> shareByCategory({
    required BuildContext context,
    required List<PurchasesByCategoryItem> items,
    required PurchaseReportsData data,
  }) async {
    final pdf = await _buildByCategoryPdf(context, items, data);
    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'PurchasesByCategory_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  /// Purchases by Supplier
  static Future<void> printBySupplier({
    required BuildContext context,
    required List<PurchasesBySupplierItem> items,
    required PurchaseReportsData data,
  }) async {
    final pdf = await _buildBySupplierPdf(context, items, data);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name:
          'PurchasesBySupplier_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> shareBySupplier({
    required BuildContext context,
    required List<PurchasesBySupplierItem> items,
    required PurchaseReportsData data,
  }) async {
    final pdf = await _buildBySupplierPdf(context, items, data);
    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'PurchasesBySupplier_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  /// Cancelled Purchases
  static Future<void> printCancelled({
    required BuildContext context,
    required List<CancelledPurchaseItem> items,
    required PurchaseReportsData data,
  }) async {
    final pdf = await _buildCancelledPdf(context, items, data);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name:
          'CancelledPurchases_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> shareCancelled({
    required BuildContext context,
    required List<CancelledPurchaseItem> items,
    required PurchaseReportsData data,
  }) async {
    final pdf = await _buildCancelledPdf(context, items, data);
    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'CancelledPurchases_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  /// Purchase Orders
  static Future<void> printOrders({
    required BuildContext context,
    required List<PurchaseOrderItem> items,
    required PurchaseReportsData data,
  }) async {
    final pdf = await _buildOrdersPdf(context, items, data);
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'PurchaseOrders_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> shareOrders({
    required BuildContext context,
    required List<PurchaseOrderItem> items,
    required PurchaseReportsData data,
  }) async {
    final pdf = await _buildOrdersPdf(context, items, data);
    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'PurchaseOrders_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  // ═══════════════════════════════════════════════════════
  // PDF BUILDERS
  // ═══════════════════════════════════════════════════════

  static Future<pw.Document> _buildInvoiceListPdf(
    BuildContext context,
    String title,
    List<PurchaseInvoiceItem> invoices,
    PurchaseReportsData data,
  ) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();
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
                '${_t('total_purchases', lang)}: ${cs.formatCents(data.summary.totalPurchasesCents)}',
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
                _t('purchase_number', lang),
                _t('supplier', lang),
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
                  i.purchaseNumber,
                  i.supplierName,
                  cs.formatCents(i.subtotalCents),
                  cs.formatCents(i.discountCents),
                  cs.formatCents(i.taxCents),
                  cs.formatCents(i.totalCents),
                  cs.formatCents(i.paidAmountCents),
                  _paymentLabel(i.paymentMethod, lang),
                  DateFormat('dd/MM/yyyy').format(i.purchaseDate),
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
    List<PurchasesByProductItem> items,
    PurchaseReportsData data,
  ) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();
    final fonts = await _loadFonts();
    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final lang = locale.languageCode;

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: dir,
        build: (pw.Context ctx) => [
          _buildHeader(company, _t('purchases_by_product', lang), fonts, dir),
          pw.SizedBox(height: 8),
          _buildPeriodLine(data, fonts, lang),
          pw.SizedBox(height: 4),
          pw.Text(
            '${_t('total_purchases', lang)}: ${cs.formatCents(data.summary.totalPurchasesCents)}  |  ${_t('products', lang)}: ${items.length}',
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
                _t('total_purchases', lang),
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
                  cs.formatCents(p.totalPurchasesCents),
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
    List<PurchasesByCategoryItem> items,
    PurchaseReportsData data,
  ) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();
    final fonts = await _loadFonts();
    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final lang = locale.languageCode;

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: dir,
        build: (pw.Context ctx) => [
          _buildHeader(company, _t('purchases_by_category', lang), fonts, dir),
          pw.SizedBox(height: 8),
          _buildPeriodLine(data, fonts, lang),
          pw.SizedBox(height: 4),
          pw.Text(
            '${_t('total_purchases', lang)}: ${cs.formatCents(data.summary.totalPurchasesCents)}  |  ${_t('categories', lang)}: ${items.length}',
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
                _t('total_purchases', lang),
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
                  cs.formatCents(c.totalPurchasesCents),
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

  static Future<pw.Document> _buildBySupplierPdf(
    BuildContext context,
    List<PurchasesBySupplierItem> items,
    PurchaseReportsData data,
  ) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();
    final fonts = await _loadFonts();
    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final lang = locale.languageCode;

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: dir,
        build: (pw.Context ctx) => [
          _buildHeader(company, _t('purchases_by_supplier', lang), fonts, dir),
          pw.SizedBox(height: 8),
          _buildPeriodLine(data, fonts, lang),
          pw.SizedBox(height: 4),
          pw.Text(
            '${_t('total_purchases', lang)}: ${cs.formatCents(data.summary.totalPurchasesCents)}  |  ${_t('suppliers', lang)}: ${items.length}',
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
                _t('supplier', lang),
                _t('total_purchases', lang),
                _t('discount', lang),
                _t('tax', lang),
                _t('invoices', lang),
                _t('quantity', lang),
                _t('last_purchase', lang),
              ],
              data: items.asMap().entries.map((e) {
                final s = e.value;
                return [
                  '${e.key + 1}',
                  s.supplierName,
                  cs.formatCents(s.totalPurchasesCents),
                  cs.formatCents(s.totalDiscountCents),
                  cs.formatCents(s.totalTaxCents),
                  '${s.invoiceCount}',
                  '${s.totalQuantity}',
                  s.lastPurchaseDate != null
                      ? DateFormat('dd/MM/yyyy').format(s.lastPurchaseDate!)
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
    List<CancelledPurchaseItem> items,
    PurchaseReportsData data,
  ) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();
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
          _buildHeader(company, _t('cancelled_purchases', lang), fonts, dir),
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
                _t('purchase_number', lang),
                _t('supplier', lang),
                _t('total', lang),
                _t('date', lang),
                _t('notes', lang),
              ],
              data: items.asMap().entries.map((e) {
                final i = e.value;
                return [
                  '${e.key + 1}',
                  i.purchaseNumber,
                  i.supplierName,
                  cs.formatCents(i.totalCents),
                  DateFormat('dd/MM/yyyy').format(i.purchaseDate),
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

  static Future<pw.Document> _buildOrdersPdf(
    BuildContext context,
    List<PurchaseOrderItem> items,
    PurchaseReportsData data,
  ) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();
    final fonts = await _loadFonts();
    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final lang = locale.languageCode;

    final totalOrders = items.fold<int>(0, (s, i) => s + i.totalCents);

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: dir,
        build: (pw.Context ctx) => [
          _buildHeader(company, _t('purchase_orders', lang), fonts, dir),
          pw.SizedBox(height: 8),
          _buildPeriodLine(data, fonts, lang),
          pw.SizedBox(height: 4),
          pw.Text(
            '${_t('total', lang)}: ${cs.formatCents(totalOrders)}  |  ${_t('orders', lang)}: ${items.length}',
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
                _t('purchase_number', lang),
                _t('supplier', lang),
                _t('total', lang),
                _t('date', lang),
                _t('due_date', lang),
              ],
              data: items.asMap().entries.map((e) {
                final o = e.value;
                return [
                  '${e.key + 1}',
                  o.purchaseNumber,
                  o.supplierName,
                  cs.formatCents(o.totalCents),
                  DateFormat('dd/MM/yyyy').format(o.purchaseDate),
                  o.dueDate != null
                      ? DateFormat('dd/MM/yyyy').format(o.dueDate!)
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
    PurchaseReportsData data,
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

  static String _paymentLabel(String? method, String lang) {
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
        return method ?? '-';
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
    'total_purchases': {
      'en': 'Total Purchases',
      'ar': 'إجمالي المشتريات',
      'fr': 'Total des Achats',
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
    'orders': {'en': 'Orders', 'ar': 'الطلبات', 'fr': 'Commandes'},
    'products': {'en': 'Products', 'ar': 'المنتجات', 'fr': 'Produits'},
    'categories': {'en': 'Categories', 'ar': 'التصنيفات', 'fr': 'Catégories'},
    'suppliers': {'en': 'Suppliers', 'ar': 'الموردين', 'fr': 'Fournisseurs'},
    'purchase_number': {
      'en': 'Purchase #',
      'ar': 'رقم الفاتورة',
      'fr': 'Achat #',
    },
    'supplier': {'en': 'Supplier', 'ar': 'المورد', 'fr': 'Fournisseur'},
    'subtotal': {'en': 'Subtotal', 'ar': 'المجموع الفرعي', 'fr': 'Sous-total'},
    'discount': {'en': 'Discount', 'ar': 'الخصم', 'fr': 'Remise'},
    'tax': {'en': 'Tax', 'ar': 'الضريبة', 'fr': 'Taxe'},
    'paid': {'en': 'Paid', 'ar': 'المدفوع', 'fr': 'Payé'},
    'payment_method': {'en': 'Payment', 'ar': 'الدفع', 'fr': 'Paiement'},
    'date': {'en': 'Date', 'ar': 'التاريخ', 'fr': 'Date'},
    'due_date': {
      'en': 'Due Date',
      'ar': 'تاريخ الاستحقاق',
      'fr': 'Date d\'échéance',
    },
    'product': {'en': 'Product', 'ar': 'المنتج', 'fr': 'Produit'},
    'category': {'en': 'Category', 'ar': 'التصنيف', 'fr': 'Catégorie'},
    'quantity': {'en': 'Qty', 'ar': 'الكمية', 'fr': 'Qté'},
    'last_purchase': {
      'en': 'Last Purchase',
      'ar': 'آخر شراء',
      'fr': 'Dernier Achat',
    },
    'notes': {'en': 'Notes', 'ar': 'ملاحظات', 'fr': 'Notes'},
    'printed_on': {'en': 'Printed on', 'ar': 'طُبع في', 'fr': 'Imprimé le'},
    'payment_cash': {'en': 'Cash', 'ar': 'نقد', 'fr': 'Espèces'},
    'payment_credit': {'en': 'Credit', 'ar': 'آجل', 'fr': 'Crédit'},
    'payment_card': {'en': 'Card', 'ar': 'بطاقة', 'fr': 'Carte'},
    'payment_cheque': {'en': 'Cheque', 'ar': 'شيك', 'fr': 'Chèque'},
    'payment_mixed': {'en': 'Mixed', 'ar': 'مختلط', 'fr': 'Mixte'},
    'purchases_by_product': {
      'en': 'Purchases by Product',
      'ar': 'المشتريات حسب الصنف',
      'fr': 'Achats par Produit',
    },
    'purchases_by_category': {
      'en': 'Purchases by Category',
      'ar': 'المشتريات حسب التصنيف',
      'fr': 'Achats par Catégorie',
    },
    'purchases_by_supplier': {
      'en': 'Purchases by Supplier',
      'ar': 'المشتريات حسب المورد',
      'fr': 'Achats par Fournisseur',
    },
    'cancelled_purchases': {
      'en': 'Cancelled Purchases',
      'ar': 'مشتريات ملغاة',
      'fr': 'Achats Annulés',
    },
    'purchase_orders': {
      'en': 'Purchase Orders',
      'ar': 'طلبات الشراء',
      'fr': 'Bons de Commande',
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
