import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:barcode_widget/barcode_widget.dart';

import '../../../core/database/daos/settings_dao.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/services/currency_service.dart';
import '../../products/domain/entities/product_entity.dart';

class PrinterConfig {
  final double widthMm;
  final double heightMm;
  final bool? includeName;
  final bool? includePrice;

  PrinterConfig({
    this.widthMm = 50,
    this.heightMm = 30,
    this.includeName,
    this.includePrice,
  });
}

class BarcodePrinterService {
  final SettingsDao _settingsDao;

  static const String keyLabelWidth = 'barcode_label_width';
  static const String keyLabelHeight = 'barcode_label_height';
  static const String keyIncludeName = 'barcode_include_name';
  static const String keyIncludePrice = 'barcode_include_price';

  BarcodePrinterService({
    required SettingsDao settingsDao,
  }) : _settingsDao = settingsDao;

  Future<void> saveSettings({
    double? widthMm,
    double? heightMm,
    bool? includeName,
    bool? includePrice,
  }) async {
    if (widthMm != null) {
      await _settingsDao.saveSetting(keyLabelWidth, widthMm.toString());
    }
    if (heightMm != null) {
      await _settingsDao.saveSetting(keyLabelHeight, heightMm.toString());
    }
    if (includeName != null) {
      await _settingsDao.saveSetting(keyIncludeName, includeName.toString());
    }
    if (includePrice != null) {
      await _settingsDao.saveSetting(keyIncludePrice, includePrice.toString());
    }
  }

  Future<PrinterConfig> getSettings() async {
    final width = await _settingsDao.getSetting(keyLabelWidth);
    final height = await _settingsDao.getSetting(keyLabelHeight);
    final incName = await _settingsDao.getSetting(keyIncludeName);
    final incPrice = await _settingsDao.getSetting(keyIncludePrice);

    return PrinterConfig(
      widthMm: double.tryParse(width ?? '') ?? 50,
      heightMm: double.tryParse(height ?? '') ?? 30,
      includeName: incName == 'true',
      includePrice: incPrice == 'true',
    );
  }

  /// Print label using PDF with system print dialog
  Future<void> printLabel({
    required Product product,
    required Barcode barcode,
    double widthMm = 58,
    double heightMm = 40,
    bool includeName = true,
    bool includePrice = true,
    bool includeCompanyName = false,
    String? companyName,
    bool includeCompanyContact = false,
    String? companyAddress,
    String? companyPhone,
    int copies = 1,
  }) async {
    await _printPdf(
      product,
      barcode,
      widthMm,
      heightMm,
      includeName,
      includePrice,
      includeCompanyName,
      companyName,
      includeCompanyContact,
      companyAddress,
      companyPhone,
      copies,
    );
  }

  Future<void> _printPdf(
    Product product,
    Barcode barcode,
    double widthMm,
    double heightMm,
    bool includeName,
    bool includePrice,
    bool includeCompanyName,
    String? companyName,
    bool includeCompanyContact,
    String? companyAddress,
    String? companyPhone,
    int copies,
  ) async {
    final doc = pw.Document();
    
    // Load multilingual font (supports Arabic, English, French)
    final fontData = await rootBundle.load('assets/fonts/IBMPlexSansArabic-Regular.ttf');
    final fontBoldData = await rootBundle.load('assets/fonts/IBMPlexSansArabic-Bold.ttf');
    final ttf = pw.Font.ttf(fontData);
    final ttfBold = pw.Font.ttf(fontBoldData);

    // Get currency service for proper formatting
    final currencyService = sl<CurrencyService>();
    final formattedPrice = currencyService.format(product.priceCents.toBigInt().toInt());

    // Detect text direction based on content
    final textDirection = _detectTextDirection(product.name);

    // Convert mm to points (1 inch = 72 points = 25.4 mm)
    final width = widthMm * PdfPageFormat.mm;
    final height = heightMm * PdfPageFormat.mm;

    // Generate the requested number of copies
    for (int i = 0; i < copies; i++) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(width, height, marginAll: 2 * PdfPageFormat.mm),
          build: (pw.Context context) {
            return pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (includeCompanyName && companyName != null && companyName.isNotEmpty)
                  pw.Text(
                    companyName,
                    style: pw.TextStyle(
                      fontSize: 7,
                      fontWeight: pw.FontWeight.bold,
                      font: ttfBold,
                    ),
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip,
                  ),
                if (includeCompanyName && companyName != null && companyName.isNotEmpty) 
                  pw.SizedBox(height: 1),
                if (includeCompanyContact &&
                    ((companyAddress != null && companyAddress.isNotEmpty) ||
                        (companyPhone != null && companyPhone.isNotEmpty))) ...[
                  if (companyAddress != null && companyAddress.isNotEmpty)
                    pw.Text(
                      companyAddress,
                      style: pw.TextStyle(
                        fontSize: 5,
                        font: ttf,
                        color: PdfColors.grey700,
                      ),
                      maxLines: 1,
                      overflow: pw.TextOverflow.clip,
                    ),
                  if (companyPhone != null && companyPhone.isNotEmpty)
                    pw.Text(
                      companyPhone,
                      style: pw.TextStyle(
                        fontSize: 5,
                        font: ttf,
                        color: PdfColors.grey700,
                      ),
                      maxLines: 1,
                      overflow: pw.TextOverflow.clip,
                    ),
                  pw.SizedBox(height: 1),
                ],
                if (includeName && product.name.isNotEmpty)
                  pw.Text(
                    product.name,
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                      font: ttfBold,
                    ),
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip,
                    textDirection: textDirection,
                  ),
                if (includeName) pw.SizedBox(height: 2),
                pw.Expanded(
                  child: pw.BarcodeWidget(
                    data: product.barcode ?? '',
                    barcode: barcode,
                    width: width - 4 * PdfPageFormat.mm,
                    height: height * 0.5,
                    drawText: true,
                    textStyle: pw.TextStyle(fontSize: 6, font: ttf),
                  ),
                ),
                if (includePrice) pw.SizedBox(height: 2),
                if (includePrice)
                  pw.Text(
                    formattedPrice,
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      font: ttfBold,
                    ),
                  ),
              ],
            );
          },
        ),
      );
    }

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Label-${product.sku ?? product.id}',
      format: PdfPageFormat(width, height),
    );
  }

  /// Detect text direction based on content (RTL for Arabic, LTR for others)
  pw.TextDirection _detectTextDirection(String text) {
    // Check for Arabic characters
    final arabicRegex = RegExp(r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]');
    if (arabicRegex.hasMatch(text)) {
      return pw.TextDirection.rtl;
    }
    return pw.TextDirection.ltr;
  }


  Future<Uint8List> generatePdfLabel({
    required Product product,
    required Barcode barcode,
    required double widthMm,
    required double heightMm,
    required bool includeName,
    required bool includePrice,
    bool includeCompanyName = false,
    String? companyName,
    bool includeCompanyContact = false,
    String? companyAddress,
    String? companyPhone,
    int copies = 1,
  }) async {
    final doc = pw.Document();
    
    // Load multilingual font (supports Arabic, English, French)
    final fontData = await rootBundle.load('assets/fonts/IBMPlexSansArabic-Regular.ttf');
    final fontBoldData = await rootBundle.load('assets/fonts/IBMPlexSansArabic-Bold.ttf');
    final ttf = pw.Font.ttf(fontData);
    final ttfBold = pw.Font.ttf(fontBoldData);

    // Get currency service for proper formatting
    final currencyService = sl<CurrencyService>();
    final formattedPrice = currencyService.format(product.priceCents.toBigInt().toInt());

    // Detect text direction based on content
    final textDirection = _detectTextDirection(product.name);

    // Convert mm to points (1 inch = 72 points = 25.4 mm)
    final width = widthMm * PdfPageFormat.mm;
    final height = heightMm * PdfPageFormat.mm;

    // Generate the requested number of copies
    for (int i = 0; i < copies; i++) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(width, height, marginAll: 2 * PdfPageFormat.mm),
          build: (pw.Context context) {
            return pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (includeCompanyName && companyName != null && companyName.isNotEmpty)
                  pw.Text(
                    companyName,
                    style: pw.TextStyle(
                      fontSize: 7,
                      fontWeight: pw.FontWeight.bold,
                      font: ttfBold,
                    ),
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip,
                  ),
                if (includeCompanyName && companyName != null && companyName.isNotEmpty) 
                  pw.SizedBox(height: 1),
                if (includeCompanyContact &&
                    ((companyAddress != null && companyAddress.isNotEmpty) ||
                        (companyPhone != null && companyPhone.isNotEmpty))) ...[
                  if (companyAddress != null && companyAddress.isNotEmpty)
                    pw.Text(
                      companyAddress,
                      style: pw.TextStyle(
                        fontSize: 5,
                        font: ttf,
                        color: PdfColors.grey700,
                      ),
                      maxLines: 1,
                      overflow: pw.TextOverflow.clip,
                    ),
                  if (companyPhone != null && companyPhone.isNotEmpty)
                    pw.Text(
                      companyPhone,
                      style: pw.TextStyle(
                        fontSize: 5,
                        font: ttf,
                        color: PdfColors.grey700,
                      ),
                      maxLines: 1,
                      overflow: pw.TextOverflow.clip,
                    ),
                  pw.SizedBox(height: 1),
                ],
                if (includeName && product.name.isNotEmpty)
                  pw.Text(
                    product.name,
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                      font: ttfBold,
                    ),
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip,
                    textDirection: textDirection,
                  ),
                if (includeName) pw.SizedBox(height: 2),
                pw.Expanded(
                  child: pw.BarcodeWidget(
                    data: product.barcode ?? '',
                    barcode: barcode,
                    width: width - 4 * PdfPageFormat.mm,
                    height: height * 0.5,
                    drawText: true,
                    textStyle: pw.TextStyle(fontSize: 6, font: ttf),
                  ),
                ),
                if (includePrice) pw.SizedBox(height: 2),
                if (includePrice)
                  pw.Text(
                    formattedPrice,
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      font: ttfBold,
                    ),
                  ),
              ],
            );
          },
        ),
      );
    }
    return await doc.save();
  }

  Future<void> shareLabelPdf({
    required Product product,
    required Barcode barcode,
    required double widthMm,
    required double heightMm,
    required bool includeName,
    required bool includePrice,
    bool includeCompanyName = false,
    String? companyName,
    bool includeCompanyContact = false,
    String? companyAddress,
    String? companyPhone,
    int copies = 1,
  }) async {
    final pdfData = await generatePdfLabel(
      product: product,
      barcode: barcode,
      widthMm: widthMm,
      heightMm: heightMm,
      includeName: includeName,
      includePrice: includePrice,
      includeCompanyName: includeCompanyName,
      companyName: companyName,
      includeCompanyContact: includeCompanyContact,
      companyAddress: companyAddress,
      companyPhone: companyPhone,
      copies: copies,
    );
    await Printing.sharePdf(bytes: pdfData, filename: 'Label-${product.sku ?? product.id}.pdf');
  }

  /// Get barcode type from string identifier
  Barcode getBarcodeTypeFromString(String typeString) {
    switch (typeString.toLowerCase()) {
      case 'code128':
      case 'code 128':
        return Barcode.code128();
      case 'ean13':
      case 'ean-13':
        return Barcode.ean13();
      case 'ean8':
      case 'ean-8':
        return Barcode.ean8();
      case 'upca':
      case 'upc-a':
        return Barcode.upcA();
      case 'qr':
      case 'qrcode':
      case 'qr code':
        return Barcode.qrCode();
      case 'auto':
      default:
        return Barcode.code128();
    }
  }

  /// Get barcode type with auto-detection based on data
  Barcode getBarcodeTypeAuto(String data, String typeString) {
    if (typeString.toLowerCase() != 'auto') {
      return getBarcodeTypeFromString(typeString);
    }

    // Auto-detect based on data format
    if (data.length == 13 && int.tryParse(data) != null) {
      return Barcode.ean13();
    }
    if (data.length == 8 && int.tryParse(data) != null) {
      return Barcode.ean8();
    }
    if (data.length == 12 && int.tryParse(data) != null) {
      return Barcode.upcA();
    }
    return Barcode.code128();
  }
}
