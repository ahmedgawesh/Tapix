import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../../settings/data/services/company_profile_service.dart';
import '../../../settings/domain/entities/company_profile.dart';

/// Data class for a stock alert item (low stock or out of stock)
class StockAlertItem {
  final int productId;
  final String productName;
  final String? sku;
  final String? barcode;
  final String? categoryName;
  final String? colorName;
  final String? colorHex;
  final String? sizeName;
  final int currentStock;
  final int reorderLevel;
  final int costCents;
  final int priceCents;
  final bool isOutOfStock;

  const StockAlertItem({
    required this.productId,
    required this.productName,
    this.sku,
    this.barcode,
    this.categoryName,
    this.colorName,
    this.colorHex,
    this.sizeName,
    required this.currentStock,
    required this.reorderLevel,
    required this.costCents,
    required this.priceCents,
    this.isOutOfStock = false,
  });

  String get variantLabel {
    final parts = <String>[];
    if (colorName != null) parts.add(colorName!);
    if (sizeName != null) parts.add(sizeName!);
    return parts.join(' / ');
  }
}

class StockAlertsPdfService {
  static Future<void> printReport({
    required BuildContext context,
    required List<StockAlertItem> outOfStock,
    required List<StockAlertItem> lowStock,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();

    final pdf = await _buildPdf(
      outOfStock: outOfStock,
      lowStock: lowStock,
      cs: cs,
      locale: locale,
      isRtl: isRtl,
      company: company,
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'StockAlerts_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> shareReport({
    required BuildContext context,
    required List<StockAlertItem> outOfStock,
    required List<StockAlertItem> lowStock,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();

    final pdf = await _buildPdf(
      outOfStock: outOfStock,
      lowStock: lowStock,
      cs: cs,
      locale: locale,
      isRtl: isRtl,
      company: company,
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'StockAlerts_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  static Future<pw.Document> _buildPdf({
    required List<StockAlertItem> outOfStock,
    required List<StockAlertItem> lowStock,
    required CurrencyService cs,
    required Locale locale,
    required bool isRtl,
    required CompanyProfile company,
  }) async {
    final fonts = await _loadFonts();
    final pdf = pw.Document();
    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final lang = locale.languageCode;

    // Out of stock page
    if (outOfStock.isNotEmpty) {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          textDirection: dir,
          build: (pw.Context context) {
            return [
              _buildHeader(company, _t('out_of_stock_title', lang), fonts, dir),
              pw.SizedBox(height: 8),
              pw.Text(
                '${_t('total_products', lang)}: ${outOfStock.length}',
                style: pw.TextStyle(font: fonts.bold, fontSize: 11, color: PdfColors.red700),
              ),
              pw.SizedBox(height: 12),
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 8),
                cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 8),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.red50),
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.centerLeft,
                  3: pw.Alignment.centerLeft,
                  4: pw.Alignment.centerLeft,
                  5: pw.Alignment.centerRight,
                  6: pw.Alignment.centerRight,
                },
                headers: [
                  _t('sku', lang),
                  _t('barcode', lang),
                  _t('product', lang),
                  _t('color_size', lang),
                  _t('category', lang),
                  _t('cost', lang),
                  _t('price', lang),
                ],
                data: outOfStock.map((item) => [
                  item.sku ?? '-',
                  item.barcode ?? '-',
                  item.productName,
                  item.variantLabel.isNotEmpty ? item.variantLabel : '-',
                  item.categoryName ?? '-',
                  cs.formatCents(item.costCents),
                  cs.formatCents(item.priceCents),
                ]).toList(),
              ),
              pw.SizedBox(height: 16),
              pw.Divider(),
              pw.Text(
                '${_t('printed_on', lang)}: ${DateFormat.yMMMd(locale.toString()).add_jm().format(DateTime.now())}',
                style: pw.TextStyle(font: fonts.regular, fontSize: 8, color: PdfColors.grey600),
              ),
            ];
          },
        ),
      );
    }

    // Low stock page
    if (lowStock.isNotEmpty) {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          textDirection: dir,
          build: (pw.Context context) {
            return [
              _buildHeader(company, _t('low_stock_title', lang), fonts, dir),
              pw.SizedBox(height: 8),
              pw.Text(
                '${_t('total_products', lang)}: ${lowStock.length}',
                style: pw.TextStyle(font: fonts.bold, fontSize: 11, color: PdfColors.orange700),
              ),
              pw.SizedBox(height: 12),
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 8),
                cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 8),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.orange50),
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.centerLeft,
                  3: pw.Alignment.centerLeft,
                  4: pw.Alignment.centerLeft,
                  5: pw.Alignment.centerRight,
                  6: pw.Alignment.centerRight,
                  7: pw.Alignment.centerRight,
                },
                headers: [
                  _t('sku', lang),
                  _t('barcode', lang),
                  _t('product', lang),
                  _t('color_size', lang),
                  _t('category', lang),
                  _t('current_stock', lang),
                  _t('reorder_level', lang),
                  _t('deficit', lang),
                ],
                data: lowStock.map((item) => [
                  item.sku ?? '-',
                  item.barcode ?? '-',
                  item.productName,
                  item.variantLabel.isNotEmpty ? item.variantLabel : '-',
                  item.categoryName ?? '-',
                  '${item.currentStock}',
                  '${item.reorderLevel}',
                  '${item.reorderLevel - item.currentStock}',
                ]).toList(),
              ),
              pw.SizedBox(height: 16),
              pw.Divider(),
              pw.Text(
                '${_t('printed_on', lang)}: ${DateFormat.yMMMd(locale.toString()).add_jm().format(DateTime.now())}',
                style: pw.TextStyle(font: fonts.regular, fontSize: 8, color: PdfColors.grey600),
              ),
            ];
          },
        ),
      );
    }

    return pdf;
  }

  // ═══════════════════════════════════════════════════════
  // 3-LANGUAGE TRANSLATIONS FOR PDF
  // ═══════════════════════════════════════════════════════

  static const _translations = {
    'out_of_stock_title': {'en': 'Out of Stock Products', 'ar': 'منتجات نفذت من المخزون', 'fr': 'Produits en Rupture de Stock'},
    'low_stock_title': {'en': 'Low Stock Products', 'ar': 'منتجات على وشك النفاذ', 'fr': 'Produits à Stock Bas'},
    'total_products': {'en': 'Total Products', 'ar': 'إجمالي المنتجات', 'fr': 'Total Produits'},
    'sku': {'en': 'SKU', 'ar': 'رمز المنتج', 'fr': 'Réf.'},
    'barcode': {'en': 'Barcode', 'ar': 'الباركود', 'fr': 'Code-barres'},
    'product': {'en': 'Product', 'ar': 'المنتج', 'fr': 'Produit'},
    'color_size': {'en': 'Color / Size', 'ar': 'اللون / المقاس', 'fr': 'Couleur / Taille'},
    'category': {'en': 'Category', 'ar': 'الفئة', 'fr': 'Catégorie'},
    'cost': {'en': 'Cost', 'ar': 'التكلفة', 'fr': 'Coût'},
    'price': {'en': 'Price', 'ar': 'السعر', 'fr': 'Prix'},
    'current_stock': {'en': 'Current', 'ar': 'الحالي', 'fr': 'Actuel'},
    'reorder_level': {'en': 'Reorder', 'ar': 'إعادة الطلب', 'fr': 'Seuil'},
    'deficit': {'en': 'Deficit', 'ar': 'العجز', 'fr': 'Déficit'},
    'printed_on': {'en': 'Printed on', 'ar': 'طُبع في', 'fr': 'Imprimé le'},
  };

  static String _t(String key, String lang) {
    return _translations[key]?[lang] ?? _translations[key]?['en'] ?? key;
  }

  // ═══════════════════════════════════════════════════════
  // HELPERS
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
            style: pw.TextStyle(font: fonts.regular, fontSize: 9, color: PdfColors.grey600),
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

  static Future<_PdfFonts> _loadFonts() async {
    try {
      final regularData = await rootBundle.load('assets/fonts/IBMPlexSansArabic-Regular.ttf');
      final boldData = await rootBundle.load('assets/fonts/IBMPlexSansArabic-Bold.ttf');
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
