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
import '../../domain/repositories/customer_repository.dart';

class CustomerTransactionPdfService {
  /// Print a customer transaction receipt
  static Future<void> printReceipt({
    required BuildContext context,
    required CustomerTransaction transaction,
    required String customerName,
    String? customerPhone,
    String? customerAddress,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();

    final pdf = await _buildReceipt(
      transaction: transaction,
      customerName: customerName,
      customerPhone: customerPhone,
      customerAddress: customerAddress,
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

  /// Share a customer transaction receipt as PDF
  static Future<void> shareReceipt({
    required BuildContext context,
    required CustomerTransaction transaction,
    required String customerName,
    String? customerPhone,
    String? customerAddress,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();

    final pdf = await _buildReceipt(
      transaction: transaction,
      customerName: customerName,
      customerPhone: customerPhone,
      customerAddress: customerAddress,
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
    required String customerName,
    String? customerPhone,
    String? customerAddress,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();
    final tx = await sl<CustomerRepository>().getTransaction(transactionId);
    if (tx == null) return;

    final pdf = await _buildReceipt(
      transaction: tx,
      customerName: customerName,
      customerPhone: customerPhone,
      customerAddress: customerAddress,
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
    required String customerName,
    String? customerPhone,
    String? customerAddress,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();
    final tx = await sl<CustomerRepository>().getTransaction(transactionId);
    if (tx == null) return;

    final pdf = await _buildReceipt(
      transaction: tx,
      customerName: customerName,
      customerPhone: customerPhone,
      customerAddress: customerAddress,
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
    required CustomerTransaction transaction,
    required String customerName,
    String? customerPhone,
    String? customerAddress,
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
      title = 'customers.payment_receipt'.tr();
      headerColor = PdfColors.blue800;
    } else if (isDiscount) {
      title = 'customers.discount_receipt'.tr();
      headerColor = PdfColors.purple800;
    } else {
      title = 'customers.receipt_type'.tr();
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
              // Header with company info
              _buildHeader(
                company: company,
                title: title,
                fonts: fonts,
                isRtl: isRtl,
                headerColor: headerColor,
              ),
              pw.SizedBox(height: 20),

              // Customer info box
              _buildCustomerInfo(
                customerName: customerName,
                customerPhone: customerPhone,
                customerAddress: customerAddress,
                fonts: fonts,
              ),
              pw.SizedBox(height: 20),

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
                      'customers.receipt_number'.tr(),
                      transaction.transactionNumber ?? 'TXN-${transaction.id}',
                      fonts.bold,
                    ),
                    pw.Divider(color: PdfColors.grey200),
                    _pdfInfoRow(
                      'customers.receipt_date'.tr(),
                      DateFormat.yMMMd(locale.toString())
                          .add_jm()
                          .format(transaction.transactionDate),
                      fonts.regular,
                    ),
                    _pdfInfoRow(
                      'customers.receipt_customer'.tr(),
                      customerName,
                      fonts.regular,
                    ),
                    _pdfInfoRow(
                      'customers.receipt_type'.tr(),
                      _localizedTransactionType(transaction.transactionType),
                      fonts.regular,
                    ),
                    if (isDiscount && transaction.discountType != null)
                      _pdfInfoRow(
                        'customers.receipt_discount_type'.tr(),
                        _localizedDiscountType(transaction.discountType!),
                        fonts.regular,
                      ),
                    if (transaction.description != null &&
                        transaction.description!.isNotEmpty)
                      _pdfInfoRow(
                        'customers.receipt_description'.tr(),
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
                      'customers.receipt_amount'.tr(),
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

              // Signature section
              _buildSignatureSection(fonts: fonts),
              pw.SizedBox(height: 20),

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
        return 'customers.transaction_payment'.tr();
      case 'discount':
        return 'customers.transaction_discount'.tr();
      case 'sale':
        return 'customers.transaction_sale'.tr();
      case 'return':
        return 'customers.transaction_return'.tr();
      case 'adjustment':
        return 'customers.transaction_adjustment'.tr();
      default:
        return type;
    }
  }

  static String _localizedDiscountType(String type) {
    switch (type) {
      case 'seasonal':
        return 'customers.discount_type_seasonal'.tr();
      case 'volume':
        return 'customers.discount_type_volume'.tr();
      case 'loyalty':
        return 'customers.discount_type_loyalty'.tr();
      case 'promotional':
        return 'customers.discount_type_promotional'.tr();
      case 'early_payment':
        return 'customers.discount_type_early_payment'.tr();
      case 'other':
        return 'customers.discount_type_other'.tr();
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
              if (company.email != null && company.email!.isNotEmpty)
                _bidiText(company.email!, fonts.regular,
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

  static pw.Widget _buildCustomerInfo({
    required String customerName,
    String? customerPhone,
    String? customerAddress,
    required _PdfFonts fonts,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
        color: PdfColors.grey50,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _bidiText('customers.customer_info_label'.tr(), fonts.bold,
              fontSize: 11, color: PdfColors.grey700),
          pw.SizedBox(height: 6),
          _pdfInfoRow('customers.receipt_customer'.tr(), customerName, fonts.regular),
          if (customerPhone != null && customerPhone.isNotEmpty)
            _pdfInfoRow('customers.phone_label'.tr(), customerPhone, fonts.regular),
          if (customerAddress != null && customerAddress.isNotEmpty)
            _pdfInfoRow('customers.address_label'.tr(), customerAddress, fonts.regular),
        ],
      ),
    );
  }

  static pw.Widget _buildSignatureSection({required _PdfFonts fonts}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 16),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            children: [
              pw.Container(
                width: 150,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400)),
                ),
                child: pw.SizedBox(height: 50),
              ),
              pw.SizedBox(height: 4),
              _bidiText('customers.company_signature'.tr(), fonts.regular,
                  fontSize: 9, color: PdfColors.grey600),
            ],
          ),
          pw.Column(
            children: [
              pw.Container(
                width: 150,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400)),
                ),
                child: pw.SizedBox(height: 50),
              ),
              pw.SizedBox(height: 4),
              _bidiText('customers.customer_signature'.tr(), fonts.regular,
                  fontSize: 9, color: PdfColors.grey600),
            ],
          ),
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
