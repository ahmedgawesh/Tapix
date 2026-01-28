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
    bool isA4Mode = false,
    int labelsPerRow = 3,
    double horizontalGapMm = 2.0,
    double verticalGapMm = 2.0,
    double pageMarginMm = 10.0,
    String? variantInfo,
    bool includeVariantInfo = false,
  }) async {
    if (isA4Mode) {
      await _printA4Grid(
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
        labelsPerRow: labelsPerRow,
        horizontalGapMm: horizontalGapMm,
        verticalGapMm: verticalGapMm,
        pageMarginMm: pageMarginMm,
        variantInfo: variantInfo,
        includeVariantInfo: includeVariantInfo,
      );
    } else {
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
        variantInfo,
        includeVariantInfo,
      );
    }
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
    String? variantInfo,
    bool includeVariantInfo,
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

  /// Print labels in A4 grid layout
  Future<void> _printA4Grid({
    required Product product,
    required Barcode barcode,
    required double widthMm,
    required double heightMm,
    required bool includeName,
    required bool includePrice,
    required bool includeCompanyName,
    required String? companyName,
    required bool includeCompanyContact,
    required String? companyAddress,
    required String? companyPhone,
    required int copies,
    required int labelsPerRow,
    required double horizontalGapMm,
    required double verticalGapMm,
    required double pageMarginMm,
    required String? variantInfo,
    required bool includeVariantInfo,
  }) async {
    final doc = pw.Document();
    
    // Load multilingual fonts
    final fontData = await rootBundle.load('assets/fonts/IBMPlexSansArabic-Regular.ttf');
    final fontBoldData = await rootBundle.load('assets/fonts/IBMPlexSansArabic-Bold.ttf');
    final ttf = pw.Font.ttf(fontData);
    final ttfBold = pw.Font.ttf(fontBoldData);

    // Get currency service
    final currencyService = sl<CurrencyService>();
    final formattedPrice = currencyService.format(product.priceCents.toBigInt().toInt());
    final textDirection = _detectTextDirection(product.name);

    // A4 dimensions
    const a4HeightMm = 297.0;
    
    // Convert to points
    final labelWidth = widthMm * PdfPageFormat.mm;
    final labelHeight = heightMm * PdfPageFormat.mm;
    final hGap = horizontalGapMm * PdfPageFormat.mm;
    final vGap = verticalGapMm * PdfPageFormat.mm;
    final topMargin = pageMarginMm * PdfPageFormat.mm;
    final bottomMargin = pageMarginMm * PdfPageFormat.mm;
    final leftMargin = pageMarginMm * PdfPageFormat.mm;
    final rightMargin = pageMarginMm * PdfPageFormat.mm;

    // Calculate labels per column
    final availableHeight = a4HeightMm * PdfPageFormat.mm - (topMargin + bottomMargin);
    final labelWithVGap = labelHeight + vGap;
    final labelsPerColumn = (availableHeight / labelWithVGap).floor().clamp(1, 20);
    final labelsPerPage = labelsPerRow * labelsPerColumn;

    // Generate pages
    int remainingCopies = copies;
    while (remainingCopies > 0) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.only(
            top: topMargin,
            bottom: bottomMargin,
            left: leftMargin,
            right: rightMargin,
          ),
          build: (pw.Context context) {
            final labelsThisPage = remainingCopies < labelsPerPage ? remainingCopies : labelsPerPage;
            final rows = (labelsThisPage / labelsPerRow).ceil();

            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: List.generate(rows, (rowIndex) {
                final startIndex = rowIndex * labelsPerRow;
                final labelsInRow = (startIndex + labelsPerRow) <= labelsThisPage
                    ? labelsPerRow
                    : labelsThisPage - startIndex;

                return pw.Padding(
                  padding: pw.EdgeInsets.only(bottom: vGap),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: List.generate(labelsInRow, (colIndex) {
                      return pw.Padding(
                        padding: pw.EdgeInsets.only(right: colIndex < labelsInRow - 1 ? hGap : 0),
                        child: _buildLabelContent(
                          product: product,
                          barcode: barcode,
                          labelWidth: labelWidth,
                          labelHeight: labelHeight,
                          includeName: includeName,
                          includePrice: includePrice,
                          includeCompanyName: includeCompanyName,
                          companyName: companyName,
                          includeCompanyContact: includeCompanyContact,
                          companyAddress: companyAddress,
                          companyPhone: companyPhone,
                          formattedPrice: formattedPrice,
                          textDirection: textDirection,
                          ttf: ttf,
                          ttfBold: ttfBold,
                          variantInfo: variantInfo,
                          includeVariantInfo: includeVariantInfo,
                        ),
                      );
                    }),
                  ),
                );
              }),
            );
          },
        ),
      );
      remainingCopies -= labelsPerPage;
    }

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
      name: 'Labels-${product.sku ?? product.id}',
      format: PdfPageFormat.a4,
    );
  }

  /// Build label content widget
  pw.Widget _buildLabelContent({
    required Product product,
    required Barcode barcode,
    required double labelWidth,
    required double labelHeight,
    required bool includeName,
    required bool includePrice,
    required bool includeCompanyName,
    required String? companyName,
    required bool includeCompanyContact,
    required String? companyAddress,
    required String? companyPhone,
    required String formattedPrice,
    required pw.TextDirection textDirection,
    required pw.Font ttf,
    required pw.Font ttfBold,
    required String? variantInfo,
    required bool includeVariantInfo,
  }) {
    return pw.Container(
      width: labelWidth,
      height: labelHeight,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        color: PdfColors.white,
      ),
      padding: const pw.EdgeInsets.all(2),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (includeCompanyName && companyName != null && companyName.isNotEmpty) ...[
            pw.Text(
              companyName,
              style: pw.TextStyle(fontSize: 5, fontWeight: pw.FontWeight.bold, font: ttfBold),
              textDirection: _detectTextDirection(companyName),
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
            ),
            pw.SizedBox(height: 0.5),
          ],
          if (includeCompanyContact &&
              ((companyAddress != null && companyAddress.isNotEmpty) ||
                  (companyPhone != null && companyPhone.isNotEmpty))) ...[
            if (companyAddress != null && companyAddress.isNotEmpty)
              pw.Text(
                companyAddress,
                style: pw.TextStyle(fontSize: 4, font: ttf, color: PdfColors.grey700),
                textDirection: _detectTextDirection(companyAddress),
                maxLines: 1,
                overflow: pw.TextOverflow.clip,
              ),
            if (companyPhone != null && companyPhone.isNotEmpty)
              pw.Text(
                companyPhone,
                style: pw.TextStyle(fontSize: 4, font: ttf, color: PdfColors.grey700),
                maxLines: 1,
                overflow: pw.TextOverflow.clip,
              ),
            pw.SizedBox(height: 0.5),
          ],
          if (includeName && product.name.isNotEmpty) ...[
            pw.Text(
              product.name,
              style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold, font: ttfBold),
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
              textDirection: textDirection,
            ),
            pw.SizedBox(height: 1),
          ],
          if (includeVariantInfo && variantInfo != null && variantInfo.isNotEmpty) ...[
            pw.Text(
              variantInfo,
              style: pw.TextStyle(fontSize: 5, font: ttf, color: PdfColors.grey700),
              textDirection: _detectTextDirection(variantInfo),
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
            ),
            pw.SizedBox(height: 0.5),
          ],
          pw.Expanded(
            child: product.barcode != null && product.barcode!.isNotEmpty
                ? pw.BarcodeWidget(
                    data: product.barcode!,
                    barcode: barcode,
                    width: labelWidth - 4,
                    height: labelHeight * 0.5,
                    drawText: true,
                    textStyle: pw.TextStyle(fontSize: 5, font: ttf),
                  )
                : pw.Container(),
          ),
          if (includePrice) ...[
            pw.SizedBox(height: 1),
            pw.Text(
              formattedPrice,
              style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, font: ttfBold),
            ),
          ],
        ],
      ),
    );
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
    bool isA4Mode = false,
    int labelsPerRow = 3,
    double horizontalGapMm = 2.0,
    double verticalGapMm = 2.0,
    double pageMarginMm = 10.0,
    String? variantInfo,
    bool includeVariantInfo = false,
  }) async {
    final pdfData = isA4Mode
        ? await _generateA4GridPdf(
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
            labelsPerRow: labelsPerRow,
            horizontalGapMm: horizontalGapMm,
            verticalGapMm: verticalGapMm,
            pageMarginMm: pageMarginMm,
            variantInfo: variantInfo,
            includeVariantInfo: includeVariantInfo,
          )
        : await generatePdfLabel(
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
    await Printing.sharePdf(bytes: pdfData, filename: 'Labels-${product.sku ?? product.id}.pdf');
  }

  /// Generate A4 grid PDF as bytes
  Future<Uint8List> _generateA4GridPdf({
    required Product product,
    required Barcode barcode,
    required double widthMm,
    required double heightMm,
    required bool includeName,
    required bool includePrice,
    required bool includeCompanyName,
    required String? companyName,
    required bool includeCompanyContact,
    required String? companyAddress,
    required String? companyPhone,
    required int copies,
    required int labelsPerRow,
    required double horizontalGapMm,
    required double verticalGapMm,
    required double pageMarginMm,
    required String? variantInfo,
    required bool includeVariantInfo,
  }) async {
    final doc = pw.Document();
    
    // Load multilingual fonts
    final fontData = await rootBundle.load('assets/fonts/IBMPlexSansArabic-Regular.ttf');
    final fontBoldData = await rootBundle.load('assets/fonts/IBMPlexSansArabic-Bold.ttf');
    final ttf = pw.Font.ttf(fontData);
    final ttfBold = pw.Font.ttf(fontBoldData);

    // Get currency service
    final currencyService = sl<CurrencyService>();
    final formattedPrice = currencyService.format(product.priceCents.toBigInt().toInt());
    final textDirection = _detectTextDirection(product.name);

    // A4 dimensions
    const a4HeightMm = 297.0;
    
    // Convert to points
    final labelWidth = widthMm * PdfPageFormat.mm;
    final labelHeight = heightMm * PdfPageFormat.mm;
    final hGap = horizontalGapMm * PdfPageFormat.mm;
    final vGap = verticalGapMm * PdfPageFormat.mm;
    final topMargin = pageMarginMm * PdfPageFormat.mm;
    final bottomMargin = pageMarginMm * PdfPageFormat.mm;
    final leftMargin = pageMarginMm * PdfPageFormat.mm;
    final rightMargin = pageMarginMm * PdfPageFormat.mm;

    // Calculate labels per column
    final availableHeight = a4HeightMm * PdfPageFormat.mm - (topMargin + bottomMargin);
    final labelWithVGap = labelHeight + vGap;
    final labelsPerColumn = (availableHeight / labelWithVGap).floor().clamp(1, 20);
    final labelsPerPage = labelsPerRow * labelsPerColumn;

    // Generate pages
    int remainingCopies = copies;
    while (remainingCopies > 0) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.only(
            top: topMargin,
            bottom: bottomMargin,
            left: leftMargin,
            right: rightMargin,
          ),
          build: (pw.Context context) {
            final labelsThisPage = remainingCopies < labelsPerPage ? remainingCopies : labelsPerPage;
            final rows = (labelsThisPage / labelsPerRow).ceil();

            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: List.generate(rows, (rowIndex) {
                final startIndex = rowIndex * labelsPerRow;
                final labelsInRow = (startIndex + labelsPerRow) <= labelsThisPage
                    ? labelsPerRow
                    : labelsThisPage - startIndex;

                return pw.Padding(
                  padding: pw.EdgeInsets.only(bottom: vGap),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: List.generate(labelsInRow, (colIndex) {
                      return pw.Padding(
                        padding: pw.EdgeInsets.only(right: colIndex < labelsInRow - 1 ? hGap : 0),
                        child: _buildLabelContent(
                          product: product,
                          barcode: barcode,
                          labelWidth: labelWidth,
                          labelHeight: labelHeight,
                          includeName: includeName,
                          includePrice: includePrice,
                          includeCompanyName: includeCompanyName,
                          companyName: companyName,
                          includeCompanyContact: includeCompanyContact,
                          companyAddress: companyAddress,
                          companyPhone: companyPhone,
                          formattedPrice: formattedPrice,
                          textDirection: textDirection,
                          ttf: ttf,
                          ttfBold: ttfBold,
                          variantInfo: variantInfo,
                          includeVariantInfo: includeVariantInfo,
                        ),
                      );
                    }),
                  ),
                );
              }),
            );
          },
        ),
      );
      remainingCopies -= labelsPerPage;
    }

    return doc.save();
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
