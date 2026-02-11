import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../../settings/data/services/company_profile_service.dart';
import '../../../settings/domain/entities/company_profile.dart';
import '../../domain/repositories/supplier_repository.dart';

class SupplierTransactionPdfService {
  /// Print a supplier transaction receipt
  static Future<void> printReceipt({
    required BuildContext context,
    required SupplierTransaction transaction,
    required String supplierName,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();

    final pdf = await _buildReceipt(
      transaction: transaction,
      supplierName: supplierName,
      cs: cs,
      locale: locale,
      isRtl: isRtl,
      company: company,
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: transaction.transactionNumber ?? 'TXN-${transaction.id}',
    );
  }

  /// Share a supplier transaction receipt as PDF
  static Future<void> shareReceipt({
    required BuildContext context,
    required SupplierTransaction transaction,
    required String supplierName,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();

    final pdf = await _buildReceipt(
      transaction: transaction,
      supplierName: supplierName,
      cs: cs,
      locale: locale,
      isRtl: isRtl,
      company: company,
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename: '${transaction.transactionNumber ?? 'TXN-${transaction.id}'}.pdf',
    );
  }

  /// Print receipt by transaction ID (fetches transaction from DB)
  static Future<void> printReceiptById({
    required BuildContext context,
    required int transactionId,
    required String supplierName,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();
    final tx = await sl<SupplierRepository>().getTransaction(transactionId);
    if (tx == null) return;

    final pdf = await _buildReceipt(
      transaction: tx,
      supplierName: supplierName,
      cs: cs,
      locale: locale,
      isRtl: isRtl,
      company: company,
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: tx.transactionNumber ?? 'TXN-${tx.id}',
    );
  }

  /// Share receipt by transaction ID (fetches transaction from DB)
  static Future<void> shareReceiptById({
    required BuildContext context,
    required int transactionId,
    required String supplierName,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();
    final tx = await sl<SupplierRepository>().getTransaction(transactionId);
    if (tx == null) return;

    final pdf = await _buildReceipt(
      transaction: tx,
      supplierName: supplierName,
      cs: cs,
      locale: locale,
      isRtl: isRtl,
      company: company,
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename: '${tx.transactionNumber ?? 'TXN-${tx.id}'}.pdf',
    );
  }

  // ═══════════════════════════════════════════════════════
  // PDF BUILDING
  // ═══════════════════════════════════════════════════════

  static Future<pw.Document> _buildReceipt({
    required SupplierTransaction transaction,
    required String supplierName,
    required CurrencyService cs,
    required Locale locale,
    required bool isRtl,
    required CompanyProfile company,
  }) async {
    final fonts = await _loadFonts();
    final pdf = pw.Document();

    final isPayment = transaction.transactionType == 'payment';
    final isDiscount = transaction.transactionType == 'discount';
    final amountCents = transaction.amountCents.toDouble().round().abs();

    final String title;
    final PdfColor headerColor;
    if (isPayment) {
      title = 'suppliers.payment_receipt'.tr();
      headerColor = PdfColors.blue800;
    } else if (isDiscount) {
      title = 'suppliers.discount_receipt'.tr();
      headerColor = PdfColors.purple800;
    } else {
      title = 'suppliers.receipt_type'.tr();
      headerColor = PdfColors.grey800;
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        textDirection: isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // Header
              _buildHeader(
                company: company,
                title: title,
                fonts: fonts,
                isRtl: isRtl,
                headerColor: headerColor,
              ),
              pw.SizedBox(height: 24),

              // Receipt info box
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _pdfInfoRow(
                      'suppliers.receipt_number'.tr(),
                      transaction.transactionNumber ?? 'TXN-${transaction.id}',
                      fonts.bold,
                    ),
                    pw.Divider(color: PdfColors.grey200),
                    _pdfInfoRow(
                      'suppliers.receipt_date'.tr(),
                      DateFormat.yMMMd(locale.toString())
                          .add_jm()
                          .format(transaction.transactionDate),
                      fonts.regular,
                    ),
                    _pdfInfoRow(
                      'suppliers.receipt_supplier'.tr(),
                      supplierName,
                      fonts.regular,
                    ),
                    _pdfInfoRow(
                      'suppliers.receipt_type'.tr(),
                      _localizedTransactionType(transaction.transactionType),
                      fonts.regular,
                    ),
                    if (isDiscount && transaction.discountType != null)
                      _pdfInfoRow(
                        'suppliers.receipt_discount_type'.tr(),
                        _localizedDiscountType(transaction.discountType!),
                        fonts.regular,
                      ),
                    if (transaction.description != null &&
                        transaction.description!.isNotEmpty)
                      _pdfInfoRow(
                        'suppliers.receipt_description'.tr(),
                        transaction.description!,
                        fonts.regular,
                      ),
                  ],
                ),
              ),
              pw.SizedBox(height: 24),

              // Amount box
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 24, vertical: 20),
                decoration: pw.BoxDecoration(
                  color: isPayment
                      ? PdfColors.blue50
                      : isDiscount
                          ? PdfColors.purple50
                          : PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(
                    color: isPayment
                        ? PdfColors.blue200
                        : isDiscount
                            ? PdfColors.purple200
                            : PdfColors.grey300,
                  ),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    _bidiText(
                      'suppliers.receipt_amount'.tr(),
                      fonts.bold,
                      fontSize: 14,
                    ),
                    pw.Text(
                      cs.format(amountCents),
                      style: pw.TextStyle(
                        font: fonts.bold,
                        fontSize: 20,
                        color: headerColor,
                      ),
                    ),
                  ],
                ),
              ),
              pw.Spacer(),

              // Footer
              _buildFooter(fonts: fonts, locale: locale),
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

  static String _localizedTransactionType(String type) {
    switch (type) {
      case 'payment':
        return 'suppliers.transaction_payment'.tr();
      case 'discount':
        return 'suppliers.transaction_discount'.tr();
      case 'purchase':
        return 'suppliers.transaction_purchase'.tr();
      case 'return':
        return 'suppliers.transaction_return'.tr();
      case 'adjustment':
        return 'suppliers.transaction_adjustment'.tr();
      default:
        return type;
    }
  }

  static String _localizedDiscountType(String type) {
    switch (type) {
      case 'seasonal':
        return 'suppliers.discount_type_seasonal'.tr();
      case 'volume':
        return 'suppliers.discount_type_volume'.tr();
      case 'loyalty':
        return 'suppliers.discount_type_loyalty'.tr();
      case 'promotional':
        return 'suppliers.discount_type_promotional'.tr();
      case 'early_payment':
        return 'suppliers.discount_type_early_payment'.tr();
      case 'other':
        return 'suppliers.discount_type_other'.tr();
      default:
        return type;
    }
  }

  static Future<_PdfFonts> _loadFonts() async {
    final fontData =
        await rootBundle.load('assets/fonts/IBMPlexSansArabic-Regular.ttf');
    final fontBoldData =
        await rootBundle.load('assets/fonts/IBMPlexSansArabic-Bold.ttf');
    return _PdfFonts(
      regular: pw.Font.ttf(fontData),
      bold: pw.Font.ttf(fontBoldData),
    );
  }

  static pw.Widget _buildHeader({
    required CompanyProfile company,
    required String title,
    required _PdfFonts fonts,
    required bool isRtl,
    required PdfColor headerColor,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (company.name.isNotEmpty)
                _bidiText(company.name, fonts.bold, fontSize: 16),
              if (company.address != null && company.address!.isNotEmpty)
                _bidiText(company.address!, fonts.regular,
                    fontSize: 8, color: PdfColors.grey600),
              if (company.phone != null && company.phone!.isNotEmpty)
                _bidiText(company.phone!, fonts.regular,
                    fontSize: 8, color: PdfColors.grey600),
              if (company.taxNumber != null && company.taxNumber!.isNotEmpty)
                _bidiText('Tax: ${company.taxNumber}', fonts.regular,
                    fontSize: 8, color: PdfColors.grey600),
            ],
          ),
          _bidiText(title, fonts.bold, fontSize: 18, color: headerColor),
        ],
      ),
    );
  }

  static pw.Widget _buildFooter({
    required _PdfFonts fonts,
    required Locale locale,
  }) {
    final footerText =
        DateFormat('yyyy-MM-dd HH:mm', locale.toString()).format(DateTime.now());
    return pw.Container(
      alignment: pw.Alignment.center,
      child: _bidiText(footerText, fonts.regular,
          fontSize: 8, color: PdfColors.grey500),
    );
  }

  static bool _hasArabic(String text) {
    return RegExp(
            r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF\u0590-\u05FF]')
        .hasMatch(text);
  }

  static pw.Text _bidiText(String text, pw.Font font,
      {double fontSize = 8, PdfColor? color}) {
    return pw.Text(text,
        textDirection:
            _hasArabic(text) ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        style: pw.TextStyle(font: font, fontSize: fontSize, color: color));
  }

  static pw.Widget _pdfInfoRow(String label, String value, pw.Font font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _bidiText(label, font, fontSize: 10, color: PdfColors.grey600),
          _bidiText(value, font, fontSize: 11),
        ],
      ),
    );
  }
}

class _PdfFonts {
  final pw.Font regular;
  final pw.Font bold;

  const _PdfFonts({required this.regular, required this.bold});
}
