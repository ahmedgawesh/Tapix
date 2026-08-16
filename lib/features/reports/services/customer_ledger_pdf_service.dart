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
import '../presentation/bloc/customer_ledger_report_bloc.dart';

class CustomerLedgerPdfService {
  static Future<void> printLedger({
    required BuildContext context,
    required CustomerLedgerData data,
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
          'CustomerLedger_${data.customerName ?? ''}_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> shareLedger({
    required BuildContext context,
    required CustomerLedgerData data,
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

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename:
          'CustomerLedger_${data.customerName ?? ''}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  // ═══════════════════════════════════════════════════════
  // PDF BUILDER
  // ═══════════════════════════════════════════════════════

  static Future<pw.Document> _buildPdf({
    required CustomerLedgerData data,
    required CurrencyService cs,
    required Locale locale,
    required bool isRtl,
    required CompanyProfile company,
  }) async {
    final fonts = await _loadFonts();
    final lang = locale.languageCode;
    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;

    final pdf = pw.Document();

    // ── Build table rows ──
    final rows = <List<String>>[];

    // Opening balance
    rows.add([
      DateFormat.yMd().format(data.dateRange.startDate),
      _t('opening_balance', lang),
      '-', '-', '-', '-', '-', '-', '-', '-', '-',
      cs.formatCents(data.openingBalanceCents),
    ]);

    // Transaction rows
    for (final row in data.rows) {
      rows.add([
        DateFormat.yMd().format(row.date),
        // Sale columns
        row.saleNumber ?? '-',
        row.saleItemCount > 0 ? row.saleItemCount.toString() : '-',
        row.saleTotalCents != 0
            ? cs.formatCents(row.saleTotalCents)
            : '-',
        // Return columns
        row.returnNumber ?? '-',
        row.returnItemCount > 0 ? row.returnItemCount.toString() : '-',
        row.returnTotalCents != 0
            ? cs.formatCents(row.returnTotalCents)
            : '-',
        // Payment columns
        row.paymentAmountCents != 0
            ? cs.formatCents(row.paymentAmountCents)
            : '-',
        row.paymentNumber ?? '-',
        // Discount columns
        row.discountAmountCents != 0
            ? cs.formatCents(row.discountAmountCents)
            : '-',
        row.discountNumber ?? '-',
        // Balance
        cs.formatCents(row.runningBalanceCents),
      ]);
    }

    // Subtotals
    rows.add([
      _t('subtotals', lang),
      '-',
      data.totalSaleItems != 0
          ? data.totalSaleItems.toString()
          : '-',
      cs.formatCents(data.totalSalesCents),
      '-',
      data.totalReturnItems != 0 ? data.totalReturnItems.toString() : '-',
      cs.formatCents(data.totalReturnsCents),
      cs.formatCents(data.totalPaymentsCents),
      '-',
      cs.formatCents(data.totalDiscountsCents),
      '-',
      '-',
    ]);

    // Closing balance
    rows.add([
      DateFormat.yMd().format(data.dateRange.endDate),
      _t('closing_balance', lang),
      '-', '-', '-', '-', '-', '-', '-', '-', '-',
      cs.formatCents(data.closingBalanceCents),
    ]);

    // ── Column headers (sub-headers under each group) ──
    final headers = [
      _t('date', lang),
      _t('sale_number', lang),
      _t('sale_qty', lang),
      _t('sale_total', lang),
      _t('return_number', lang),
      _t('return_qty', lang),
      _t('return_total', lang),
      _t('payment_amount', lang),
      _t('payment_number', lang),
      _t('discount_amount', lang),
      _t('discount_number', lang),
      _t('balance', lang),
    ];

    // ── Page format: landscape A4 for wide table ──
    final pageFormat = PdfPageFormat.a4.landscape;

    // Column widths (12 columns)
    final colWidths = <int, pw.TableColumnWidth>{
      0: const pw.FlexColumnWidth(1.2), // Date
      1: const pw.FlexColumnWidth(1.2), // Sale #
      2: const pw.FlexColumnWidth(0.7), // Qty
      3: const pw.FlexColumnWidth(1.3), // Total
      4: const pw.FlexColumnWidth(1.2), // Return #
      5: const pw.FlexColumnWidth(0.7), // Qty
      6: const pw.FlexColumnWidth(1.3), // Total
      7: const pw.FlexColumnWidth(1.3), // Payment amt
      8: const pw.FlexColumnWidth(1.0), // Payment #
      9: const pw.FlexColumnWidth(1.3), // Discount amt
      10: const pw.FlexColumnWidth(1.0), // Discount #
      11: const pw.FlexColumnWidth(1.3), // Balance
    };

    // Group category labels for each column (shown above sub-headers)
    final groupLabels = [
      _t('date', lang),
      _t('sale_invoices', lang),
      _t('sale_invoices', lang),
      _t('sale_invoices', lang),
      _t('return_invoices', lang),
      _t('return_invoices', lang),
      _t('return_invoices', lang),
      _t('payments_group', lang),
      _t('payments_group', lang),
      _t('discounts_group', lang),
      _t('discounts_group', lang),
      _t('balance', lang),
    ];

    pdf.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        textDirection: dir,
        margin: const pw.EdgeInsets.all(24),
        header: (ctx) => _buildHeader(company, data, fonts, dir, lang),
        footer: (ctx) => _buildFooter(fonts, locale, ctx),
        build: (ctx) => [
          pw.SizedBox(height: 8),
          // Summary row
          _buildSummaryRow(data, cs, fonts, lang),
          pw.SizedBox(height: 12),
          // Main table
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            columnWidths: colWidths,
            children: [
              // Group category labels row
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.blue50),
                children: groupLabels.map((g) {
                  return pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3),
                    alignment: pw.Alignment.center,
                    child: pw.Text(
                      g,
                      style: pw.TextStyle(
                        font: fonts.bold,
                        fontSize: 6,
                        color: PdfColors.blue900,
                      ),
                      textDirection: dir,
                      textAlign: pw.TextAlign.center,
                    ),
                  );
                }).toList(),
              ),
              // Sub-headers row
              pw.TableRow(
                decoration:
                    const pw.BoxDecoration(color: PdfColors.grey200),
                children: headers.map((h) {
                  return pw.Container(
                    padding: const pw.EdgeInsets.all(3),
                    alignment: pw.Alignment.center,
                    child: pw.Text(
                      h,
                      style: pw.TextStyle(
                        font: fonts.bold,
                        fontSize: 6.5,
                        color: PdfColors.grey800,
                      ),
                      textDirection: dir,
                      textAlign: pw.TextAlign.center,
                    ),
                  );
                }).toList(),
              ),
              // Data rows
              ...rows.asMap().entries.map((entry) {
                final idx = entry.key;
                final cells = entry.value;
                final isFirst = idx == 0;
                final isSubtotal = idx == rows.length - 2;
                final isLast = idx == rows.length - 1;
                final isSpecial = isFirst || isSubtotal || isLast;

                return pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: isSpecial
                        ? PdfColors.grey100
                        : (idx.isEven
                            ? PdfColors.white
                            : PdfColors.grey50),
                  ),
                  children: cells.asMap().entries.map((cellEntry) {
                    final cellIdx = cellEntry.key;
                    final cellText = cellEntry.value;
                    final isBalance = cellIdx == 11;
                    final isSaleAmt = cellIdx == 3;
                    final isReturnAmt = cellIdx == 6;
                    final isPaymentAmt = cellIdx == 7;
                    final isDiscountAmt = cellIdx == 9;

                    PdfColor textColor = PdfColors.black;
                    if (isBalance && !isSubtotal) {
                      textColor = PdfColors.blue900;
                    } else if (isSaleAmt && cellText != '-') {
                      textColor = PdfColors.red800;
                    } else if (isReturnAmt && cellText != '-') {
                      textColor = PdfColors.green800;
                    } else if (isPaymentAmt && cellText != '-') {
                      textColor = PdfColors.blue800;
                    } else if (isDiscountAmt && cellText != '-') {
                      textColor = PdfColors.purple800;
                    }

                    return pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 3, vertical: 2),
                      alignment: pw.Alignment.center,
                      child: pw.Text(
                        cellText,
                        style: pw.TextStyle(
                          font: isSpecial ? fonts.bold : fonts.regular,
                          fontSize: 6.5,
                          color: textColor,
                        ),
                        textDirection: dir,
                        textAlign: pw.TextAlign.center,
                      ),
                    );
                  }).toList(),
                );
              }),
            ],
          ),
        ],
      ),
    );

    return pdf;
  }

  // ═══════════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════════

  static pw.Widget _buildHeader(
    CompanyProfile company,
    CustomerLedgerData data,
    _PdfFonts fonts,
    pw.TextDirection dir,
    String lang,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  company.name,
                  style: pw.TextStyle(font: fonts.bold, fontSize: 14),
                  textDirection: dir,
                ),
                if (company.address != null && company.address!.isNotEmpty)
                  pw.Text(
                    company.address!,
                    style: pw.TextStyle(
                      font: fonts.regular,
                      fontSize: 8,
                      color: PdfColors.grey600,
                    ),
                    textDirection: dir,
                  ),
                if (company.phone != null && company.phone!.isNotEmpty)
                  pw.Text(
                    company.phone!,
                    style: pw.TextStyle(
                      font: fonts.regular,
                      fontSize: 8,
                      color: PdfColors.grey600,
                    ),
                    textDirection: dir,
                  ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  _t('title', lang),
                  style: pw.TextStyle(font: fonts.bold, fontSize: 12),
                  textDirection: dir,
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  '${_t('customer', lang)}: ${data.customerName ?? ''}',
                  style: pw.TextStyle(font: fonts.regular, fontSize: 9),
                  textDirection: dir,
                ),
                pw.Text(
                  '${_t('period', lang)}: ${DateFormat.yMd().format(data.dateRange.startDate)} - ${DateFormat.yMd().format(data.dateRange.endDate)}',
                  style: pw.TextStyle(
                    font: fonts.regular,
                    fontSize: 8,
                    color: PdfColors.grey600,
                  ),
                  textDirection: dir,
                ),
              ],
            ),
          ],
        ),
        pw.Divider(),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // SUMMARY ROW
  // ═══════════════════════════════════════════════════════

  static pw.Widget _buildSummaryRow(
    CustomerLedgerData data,
    CurrencyService cs,
    _PdfFonts fonts,
    String lang,
  ) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
      children: [
        _summaryBox(_t('total_sales', lang),
            cs.formatCents(data.totalSalesCents), PdfColors.red800, fonts),
        _summaryBox(_t('total_returns', lang),
            cs.formatCents(data.totalReturnsCents), PdfColors.green800, fonts),
        _summaryBox(_t('total_payments', lang),
            cs.formatCents(data.totalPaymentsCents), PdfColors.blue800, fonts),
        _summaryBox(
            _t('total_discounts', lang),
            cs.formatCents(data.totalDiscountsCents),
            PdfColors.purple800,
            fonts),
        _summaryBox(
            _t('closing_balance', lang),
            cs.formatCents(data.closingBalanceCents),
            data.closingBalanceCents > 0
                ? PdfColors.red800
                : PdfColors.green800,
            fonts),
      ],
    );
  }

  static pw.Widget _summaryBox(
      String label, String value, PdfColor color, _PdfFonts fonts) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        children: [
          pw.Text(label,
              style: pw.TextStyle(
                  font: fonts.regular,
                  fontSize: 7,
                  color: PdfColors.grey700)),
          pw.SizedBox(height: 2),
          pw.Text(value,
              style:
                  pw.TextStyle(font: fonts.bold, fontSize: 8, color: color)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // FOOTER
  // ═══════════════════════════════════════════════════════

  static pw.Widget _buildFooter(
      _PdfFonts fonts, Locale locale, pw.Context ctx) {
    final footerText =
        DateFormat('yyyy-MM-dd HH:mm', locale.toString()).format(DateTime.now());
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          footerText,
          style: pw.TextStyle(
              font: fonts.regular, fontSize: 7, color: PdfColors.grey500),
        ),
        pw.Text(
          '${ctx.pageNumber} / ${ctx.pagesCount}',
          style: pw.TextStyle(
              font: fonts.regular, fontSize: 7, color: PdfColors.grey500),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // TRANSLATIONS
  // ═══════════════════════════════════════════════════════

  static const _translations = <String, Map<String, String>>{
    'title': {
      'en': 'Customer Ledger Account Statement',
      'ar': 'كشف حساب عميل دفتري',
      'fr': 'Relevé de Compte Client',
    },
    'customer': {
      'en': 'Customer',
      'ar': 'العميل',
      'fr': 'Client',
    },
    'period': {
      'en': 'Period',
      'ar': 'الفترة',
      'fr': 'Période',
    },
    'date': {
      'en': 'Date',
      'ar': 'التاريخ',
      'fr': 'Date',
    },
    'sale_invoices': {
      'en': 'Sale Invoices',
      'ar': 'فواتير المبيعات',
      'fr': 'Factures de Vente',
    },
    'return_invoices': {
      'en': 'Return Invoices',
      'ar': 'فواتير المرتجعات',
      'fr': 'Factures de Retour',
    },
    'payments_group': {
      'en': 'Payments',
      'ar': 'الدفعات',
      'fr': 'Paiements',
    },
    'discounts_group': {
      'en': 'Discounts',
      'ar': 'الخصومات',
      'fr': 'Remises',
    },
    'sale_number': {
      'en': 'Invoice #',
      'ar': 'رقم الفاتورة',
      'fr': 'N° Facture',
    },
    'sale_qty': {
      'en': 'Qty',
      'ar': 'عدد القطع',
      'fr': 'Qté',
    },
    'sale_total': {
      'en': 'Total',
      'ar': 'اجمالي الفاتورة',
      'fr': 'Total',
    },
    'return_number': {
      'en': 'Invoice #',
      'ar': 'رقم الفاتورة',
      'fr': 'N° Facture',
    },
    'return_qty': {
      'en': 'Qty',
      'ar': 'عدد القطع',
      'fr': 'Qté',
    },
    'return_total': {
      'en': 'Total',
      'ar': 'اجمالي الفاتورة',
      'fr': 'Total',
    },
    'payment_amount': {
      'en': 'Payment Amount',
      'ar': 'قيمة الدفعة',
      'fr': 'Montant Paiement',
    },
    'payment_number': {
      'en': 'Payment #',
      'ar': 'رقمها',
      'fr': 'N° Paiement',
    },
    'discount_amount': {
      'en': 'Discount Amount',
      'ar': 'قيمة الخصم',
      'fr': 'Montant Remise',
    },
    'discount_number': {
      'en': 'Discount #',
      'ar': 'رقمه',
      'fr': 'N° Remise',
    },
    'balance': {
      'en': 'Balance',
      'ar': 'الرصيد',
      'fr': 'Solde',
    },
    'opening_balance': {
      'en': 'Opening Balance',
      'ar': 'رصيد افتتاحي',
      'fr': 'Solde d\'Ouverture',
    },
    'closing_balance': {
      'en': 'Closing Balance',
      'ar': 'رصيد ختامي',
      'fr': 'Solde de Clôture',
    },
    'subtotals': {
      'en': 'Subtotals',
      'ar': 'الاجمالي الفرعي',
      'fr': 'Sous-totaux',
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
    'total_payments': {
      'en': 'Total Payments',
      'ar': 'إجمالي الدفعات',
      'fr': 'Total Paiements',
    },
    'total_discounts': {
      'en': 'Total Discounts',
      'ar': 'إجمالي الخصومات',
      'fr': 'Total Remises',
    },
  };

  static String _t(String key, String lang) {
    return _translations[key]?[lang] ?? _translations[key]?['en'] ?? key;
  }

  // ═══════════════════════════════════════════════════════
  // FONTS
  // ═══════════════════════════════════════════════════════

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
