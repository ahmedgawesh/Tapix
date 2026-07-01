import 'dart:ui' show Locale;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/services/currency_service.dart';
import '../../settings/domain/entities/company_profile.dart';
import '../presentation/bloc/customer_invoices_report_bloc.dart' show InvoiceLineItem;

/// A locale-agnostic view model for a single invoice rendered in the PDF.
class InvoicePdfItem {
  final String invoiceNumber;
  final String? referenceLabel;
  final DateTime date;
  final List<InvoiceLineItem> items;
  final int subtotalCents;
  final int discountCents;
  final int taxCents;
  final int totalCents;
  final int paidAmountCents;
  final String? paymentMethod;

  const InvoicePdfItem({
    required this.invoiceNumber,
    this.referenceLabel,
    required this.date,
    required this.items,
    required this.subtotalCents,
    required this.discountCents,
    required this.taxCents,
    required this.totalCents,
    required this.paidAmountCents,
    this.paymentMethod,
  });
}

class InvoicesPdfFonts {
  final pw.Font regular;
  final pw.Font bold;
  InvoicesPdfFonts({required this.regular, required this.bold});
}

/// Shared PDF builder for both the customer-invoices and supplier-invoices
/// reports. Keeps the layout identical across the two reports.
class InvoicesPdfBuilder {
  static Future<pw.Document> build({
    required String title,
    required String partyLabel,
    required String partyName,
    String? partyPhone,
    String? partyAddress,
    required DateTime startDate,
    required DateTime endDate,
    required List<InvoicePdfItem> invoices,
    required int totalAmountCents,
    required int totalDiscountCents,
    required int totalPaidCents,
    required int totalQuantity,
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
            _header(company, title, fonts),
            pw.SizedBox(height: 8),
            pw.Text(
              '${_t('period', lang)}: ${DateFormat.yMMMd().format(startDate)} — ${DateFormat.yMMMd().format(endDate)}',
              style: pw.TextStyle(font: fonts.regular, fontSize: 10),
            ),
            pw.SizedBox(height: 8),
            _partyInfo(partyLabel, partyName, partyPhone, partyAddress, fonts, lang),
            pw.SizedBox(height: 10),
            _summary(cs, fonts, lang, invoices.length, totalQuantity,
                totalAmountCents, totalDiscountCents, totalPaidCents),
            pw.SizedBox(height: 12),
            if (invoices.isEmpty)
              pw.Text(
                _t('no_invoices', lang),
                style: pw.TextStyle(
                    font: fonts.regular,
                    fontSize: 10,
                    color: PdfColors.grey600),
              )
            else
              ...invoices.map((inv) => _invoiceBlock(inv, cs, fonts, lang)),
            pw.SizedBox(height: 16),
            pw.Divider(),
            pw.Text(
              '${_t('printed_on', lang)}: ${DateFormat.yMMMd().add_jm().format(DateTime.now())}',
              style: pw.TextStyle(
                  font: fonts.regular, fontSize: 8, color: PdfColors.grey600),
            ),
          ];
        },
      ),
    );

    return pdf;
  }

  static pw.Widget _invoiceBlock(
    InvoicePdfItem inv,
    CurrencyService cs,
    InvoicesPdfFonts fonts,
    String lang,
  ) {
    final dueCents = inv.totalCents - inv.paidAmountCents;
    final rows = <List<String>>[];
    for (final item in inv.items) {
      final name = item.variantLabel == null
          ? item.productName
          : '${item.productName} (${item.variantLabel})';
      rows.add([
        name,
        item.quantity.toString(),
        cs.formatCents(item.unitPriceCents),
        cs.formatCents(item.totalCents),
      ]);
    }

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Header
          pw.Container(
            width: double.infinity,
            color: PdfColors.grey200,
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(inv.invoiceNumber,
                          style: pw.TextStyle(font: fonts.bold, fontSize: 10)),
                      if (inv.referenceLabel != null)
                        pw.Text(inv.referenceLabel!,
                            style: pw.TextStyle(
                                font: fonts.regular,
                                fontSize: 8,
                                color: PdfColors.grey700)),
                    ],
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(DateFormat.yMd().format(inv.date),
                        style: pw.TextStyle(font: fonts.regular, fontSize: 8)),
                    pw.Text(_paymentMethod(inv.paymentMethod, lang),
                        style: pw.TextStyle(font: fonts.bold, fontSize: 8)),
                  ],
                ),
              ],
            ),
          ),
          // Items
          if (rows.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 8),
                cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 8),
                headerDecoration:
                    const pw.BoxDecoration(color: PdfColors.grey100),
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.center,
                  2: pw.Alignment.centerRight,
                  3: pw.Alignment.centerRight,
                },
                columnWidths: {
                  0: const pw.FlexColumnWidth(4),
                  1: const pw.FlexColumnWidth(1.2),
                  2: const pw.FlexColumnWidth(2),
                  3: const pw.FlexColumnWidth(2),
                },
                headers: [
                  _t('product', lang),
                  _t('qty', lang),
                  _t('unit_price', lang),
                  _t('line_total', lang),
                ],
                data: rows,
              ),
            ),
          // Totals
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(8, 2, 8, 8),
            child: pw.Column(
              children: [
                _totalRow(_t('subtotal', lang),
                    cs.formatCents(inv.subtotalCents), fonts),
                if (inv.discountCents > 0)
                  _totalRow(_t('discount', lang),
                      '- ${cs.formatCents(inv.discountCents)}', fonts),
                if (inv.taxCents > 0)
                  _totalRow(
                      _t('tax', lang), cs.formatCents(inv.taxCents), fonts),
                _totalRow(_t('total', lang), cs.formatCents(inv.totalCents),
                    fonts,
                    bold: true),
                _totalRow(_t('paid', lang),
                    cs.formatCents(inv.paidAmountCents), fonts),
                if (dueCents > 0)
                  _totalRow(
                      _t('due', lang), cs.formatCents(dueCents), fonts,
                      bold: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _totalRow(String label, String value, InvoicesPdfFonts fonts,
      {bool bold = false}) {
    final font = bold ? fonts.bold : fonts.regular;
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(font: font, fontSize: 8)),
          pw.Text(value, style: pw.TextStyle(font: font, fontSize: 8)),
        ],
      ),
    );
  }

  static pw.Widget _summary(
    CurrencyService cs,
    InvoicesPdfFonts fonts,
    String lang,
    int invoiceCount,
    int totalQuantity,
    int totalAmountCents,
    int totalDiscountCents,
    int totalPaidCents,
  ) {
    return pw.TableHelper.fromTextArray(
      headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 9),
      cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 9),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellAlignments: {
        0: pw.Alignment.center,
        1: pw.Alignment.center,
        2: pw.Alignment.center,
        3: pw.Alignment.center,
        4: pw.Alignment.center,
      },
      headers: [
        _t('invoices_count', lang),
        _t('total_quantity', lang),
        _t('total_amount', lang),
        _t('total_discount', lang),
        _t('total_paid', lang),
      ],
      data: [
        [
          invoiceCount.toString(),
          totalQuantity.toString(),
          cs.formatCents(totalAmountCents),
          cs.formatCents(totalDiscountCents),
          cs.formatCents(totalPaidCents),
        ],
      ],
    );
  }

  static pw.Widget _partyInfo(
    String partyLabel,
    String name,
    String? phone,
    String? address,
    InvoicesPdfFonts fonts,
    String lang,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('$partyLabel: $name',
              style: pw.TextStyle(font: fonts.bold, fontSize: 11)),
          if (phone != null && phone.isNotEmpty)
            pw.Text('${_t('phone', lang)}: $phone',
                style: pw.TextStyle(font: fonts.regular, fontSize: 9)),
          if (address != null && address.isNotEmpty)
            pw.Text('${_t('address', lang)}: $address',
                style: pw.TextStyle(font: fonts.regular, fontSize: 9)),
        ],
      ),
    );
  }

  static pw.Widget _header(
      CompanyProfile company, String title, InvoicesPdfFonts fonts) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(company.name,
            style: pw.TextStyle(font: fonts.bold, fontSize: 16)),
        if (company.address != null && company.address!.isNotEmpty)
          pw.Text(company.address!,
              style: pw.TextStyle(
                  font: fonts.regular, fontSize: 9, color: PdfColors.grey600)),
        pw.SizedBox(height: 8),
        pw.Divider(),
        pw.SizedBox(height: 4),
        pw.Center(
          child: pw.Text(title,
              style: pw.TextStyle(font: fonts.bold, fontSize: 14)),
        ),
      ],
    );
  }

  // ── translations ──
  static const _translations = {
    'period': {'en': 'Period', 'ar': 'الفترة', 'fr': 'Période'},
    'phone': {'en': 'Phone', 'ar': 'الهاتف', 'fr': 'Téléphone'},
    'address': {'en': 'Address', 'ar': 'العنوان', 'fr': 'Adresse'},
    'invoices_count': {
      'en': 'Invoices',
      'ar': 'عدد الفواتير',
      'fr': 'Factures'
    },
    'total_quantity': {
      'en': 'Quantity',
      'ar': 'إجمالي الكمية',
      'fr': 'Quantité'
    },
    'total_amount': {'en': 'Total', 'ar': 'الإجمالي', 'fr': 'Total'},
    'total_discount': {'en': 'Discount', 'ar': 'الخصم', 'fr': 'Remise'},
    'total_paid': {'en': 'Paid', 'ar': 'المدفوع', 'fr': 'Payé'},
    'product': {'en': 'Product', 'ar': 'الصنف', 'fr': 'Produit'},
    'qty': {'en': 'Qty', 'ar': 'الكمية', 'fr': 'Qté'},
    'unit_price': {
      'en': 'Unit Price',
      'ar': 'سعر الوحدة',
      'fr': 'Prix unitaire'
    },
    'line_total': {'en': 'Total', 'ar': 'الإجمالي', 'fr': 'Total'},
    'subtotal': {'en': 'Subtotal', 'ar': 'المجموع الفرعي', 'fr': 'Sous-total'},
    'discount': {'en': 'Discount', 'ar': 'الخصم', 'fr': 'Remise'},
    'tax': {'en': 'Tax', 'ar': 'الضريبة', 'fr': 'Taxe'},
    'total': {'en': 'Total', 'ar': 'الإجمالي', 'fr': 'Total'},
    'paid': {'en': 'Paid', 'ar': 'المدفوع', 'fr': 'Payé'},
    'due': {'en': 'Due', 'ar': 'المتبقي', 'fr': 'Dû'},
    'no_invoices': {
      'en': 'No invoices in this period',
      'ar': 'لا توجد فواتير في هذه الفترة',
      'fr': 'Aucune facture pour cette période'
    },
    'printed_on': {'en': 'Printed on', 'ar': 'طُبع في', 'fr': 'Imprimé le'},
    'pm_cash': {'en': 'Cash', 'ar': 'نقدي', 'fr': 'Espèces'},
    'pm_card': {'en': 'Card', 'ar': 'بطاقة', 'fr': 'Carte'},
    'pm_credit': {'en': 'Credit', 'ar': 'آجل', 'fr': 'Crédit'},
    'pm_cheque': {'en': 'Cheque', 'ar': 'شيك', 'fr': 'Chèque'},
    'pm_bank_transfer': {
      'en': 'Bank Transfer',
      'ar': 'تحويل بنكي',
      'fr': 'Virement'
    },
    'pm_mobile': {'en': 'Mobile', 'ar': 'محفظة', 'fr': 'Mobile'},
  };

  static String _t(String key, String lang) =>
      _translations[key]?[lang] ?? _translations[key]?['en'] ?? key;

  static String _paymentMethod(String? method, String lang) {
    if (method == null || method.isEmpty) return '-';
    final key = 'pm_$method';
    return _translations[key]?[lang] ?? _translations[key]?['en'] ?? method;
  }

  static Future<InvoicesPdfFonts> _loadFonts() async {
    try {
      final regularData =
          await rootBundle.load('assets/fonts/IBMPlexSansArabic-Regular.ttf');
      final boldData =
          await rootBundle.load('assets/fonts/IBMPlexSansArabic-Bold.ttf');
      return InvoicesPdfFonts(
        regular: pw.Font.ttf(regularData),
        bold: pw.Font.ttf(boldData),
      );
    } catch (_) {
      return InvoicesPdfFonts(
        regular: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
      );
    }
  }
}
