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
import '../presentation/bloc/inventory_reports_bloc.dart';

class InventoryPdfService {
  static Future<void> printInventoryReport({
    required BuildContext context,
    required InventoryReportsData data,
    PriceDisplayType priceType = PriceDisplayType.cost,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();

    final pdf = await _buildInventoryPdf(
      data: data,
      cs: cs,
      locale: locale,
      isRtl: isRtl,
      company: company,
      priceType: priceType,
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'InventoryReport_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> shareInventoryReport({
    required BuildContext context,
    required InventoryReportsData data,
    PriceDisplayType priceType = PriceDisplayType.cost,
  }) async {
    final cs = sl<CurrencyService>();
    final locale = context.locale;
    final isRtl = locale.languageCode == 'ar';
    final company = await sl<CompanyProfileService>().getProfile();

    final pdf = await _buildInventoryPdf(
      data: data,
      cs: cs,
      locale: locale,
      isRtl: isRtl,
      company: company,
      priceType: priceType,
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'InventoryReport_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  static Future<pw.Document> _buildInventoryPdf({
    required InventoryReportsData data,
    required CurrencyService cs,
    required Locale locale,
    required bool isRtl,
    required CompanyProfile company,
    PriceDisplayType priceType = PriceDisplayType.cost,
  }) async {
    final fonts = await _loadFonts();
    final pdf = pw.Document();
    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final lang = locale.languageCode;

    // Compute total valuation based on selected price type
    int totalValuation = 0;
    for (final item in data.stockValuation) {
      totalValuation += item.valuationByType(priceType);
    }

    // Page 1: Stock Valuation
    if (data.stockValuation.isNotEmpty) {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          textDirection: dir,
          build: (pw.Context context) {
            return [
              _buildHeader(company, _t('stock_valuation', lang), fonts, dir),
              pw.SizedBox(height: 8),
              pw.Text(
                '${_t('period', lang)}: ${DateFormat.yMMMd().format(data.dateRange.startDate)} — ${DateFormat.yMMMd().format(data.dateRange.endDate)}',
                style: pw.TextStyle(font: fonts.regular, fontSize: 10),
              ),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    '${_t('total_valuation', lang)}: ${cs.formatCents(totalValuation)}',
                    style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                  ),
                  pw.Text(
                    '${_t('total_stock_units', lang)}: ${data.totalStockUnits}',
                    style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 8),
                cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 8),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.centerLeft,
                  3: pw.Alignment.centerLeft,
                  4: pw.Alignment.centerRight,
                  5: pw.Alignment.centerRight,
                  6: pw.Alignment.centerRight,
                },
                headers: [
                  _t('sku', lang),
                  _t('product', lang),
                  _t('color_size', lang),
                  _t('category', lang),
                  _t('stock', lang),
                  _priceTypeLabel(priceType, lang),
                  _t('valuation', lang),
                ],
                data: data.stockValuation.map((item) => [
                  item.sku ?? '-',
                  item.productName,
                  item.variantLabel.isNotEmpty ? item.variantLabel : '-',
                  item.categoryName ?? '-',
                  '${item.totalStock}',
                  cs.formatCents(item.priceByType(priceType)),
                  cs.formatCents(item.valuationByType(priceType)),
                ]).toList(),
              ),
              pw.SizedBox(height: 8),
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      '${_t('total_valuation', lang)}:',
                      style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                    ),
                    pw.Text(
                      cs.formatCents(totalValuation),
                      style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),
              pw.Divider(),
              pw.Text(
                '${_t('printed_on', lang)}: ${DateFormat.yMMMd().add_jm().format(DateTime.now())}',
                style: pw.TextStyle(font: fonts.regular, fontSize: 8, color: PdfColors.grey600),
              ),
            ];
          },
        ),
      );
    }

    // Page 2: Low Stock
    if (data.lowStockItems.isNotEmpty) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          textDirection: dir,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _buildHeader(company, _t('low_stock', lang), fonts, dir),
                pw.SizedBox(height: 8),
                pw.Text(
                  '${_t('low_stock_alert', lang)}: ${data.lowStockItems.length}',
                  style: pw.TextStyle(font: fonts.bold, fontSize: 11, color: PdfColors.red700),
                ),
                pw.SizedBox(height: 12),
                pw.TableHelper.fromTextArray(
                  headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 9),
                  cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 9),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  cellAlignments: {
                    0: pw.Alignment.centerLeft,
                    1: pw.Alignment.centerLeft,
                    2: pw.Alignment.centerLeft,
                    3: pw.Alignment.centerRight,
                    4: pw.Alignment.centerRight,
                    5: pw.Alignment.centerRight,
                  },
                  headers: [
                    _t('sku', lang),
                    _t('product', lang),
                    _t('color_size', lang),
                    _t('current_stock', lang),
                    _t('reorder_level', lang),
                    _t('deficit', lang),
                  ],
                  data: data.lowStockItems.map((item) => [
                    item.sku ?? '-',
                    item.productName,
                    item.variantLabel.isNotEmpty ? item.variantLabel : '-',
                    '${item.currentStock}',
                    '${item.reorderLevel}',
                    '${item.deficit}',
                  ]).toList(),
                ),
                pw.Spacer(),
                pw.Divider(),
                pw.Text(
                  '${_t('printed_on', lang)}: ${DateFormat.yMMMd().add_jm().format(DateTime.now())}',
                  style: pw.TextStyle(font: fonts.regular, fontSize: 8, color: PdfColors.grey600),
                ),
              ],
            );
          },
        ),
      );
    }

    // Page 3: Product Movement
    if (data.productMovement.isNotEmpty) {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          textDirection: dir,
          build: (pw.Context context) {
            final filterParts = <String>[];
            if (data.movementCategoryName != null) {
              filterParts.add('${_t('category', lang)}: ${data.movementCategoryName}');
            }
            if (data.movementSupplierName != null) {
              filterParts.add('${_t('supplier', lang)}: ${data.movementSupplierName}');
            }
            if (data.movementSearchQuery.isNotEmpty) {
              filterParts.add('${_t('search', lang)}: ${data.movementSearchQuery}');
            }

            return [
              _buildHeader(company, _t('product_movement', lang), fonts, dir),
              pw.SizedBox(height: 8),
              pw.Text(
                '${_t('period', lang)}: ${DateFormat.yMMMd().format(data.dateRange.startDate)} — ${DateFormat.yMMMd().format(data.dateRange.endDate)}',
                style: pw.TextStyle(font: fonts.regular, fontSize: 10),
              ),
              if (filterParts.isNotEmpty) ...[  
                pw.SizedBox(height: 4),
                pw.Text(
                  filterParts.join('  |  '),
                  style: pw.TextStyle(font: fonts.regular, fontSize: 9, color: PdfColors.grey700),
                ),
              ],
              pw.SizedBox(height: 12),
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 8),
                cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 8),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.centerLeft,
                  3: pw.Alignment.centerRight,
                  4: pw.Alignment.centerRight,
                  5: pw.Alignment.centerRight,
                  6: pw.Alignment.centerRight,
                  7: pw.Alignment.centerRight,
                },
                headers: [
                  _t('sku', lang),
                  _t('product', lang),
                  _t('color_size', lang),
                  _t('purchased', lang),
                  _t('sold', lang),
                  _t('sale_returned', lang),
                  _t('purchase_returned', lang),
                  _t('net_movement', lang),
                ],
                data: data.productMovement.map((item) => [
                  item.sku ?? '-',
                  item.productName,
                  item.variantLabel.isNotEmpty ? item.variantLabel : '-',
                  '+${item.purchasedQty}',
                  '-${item.soldQty}',
                  '+${item.saleReturnedQty}',
                  '-${item.purchaseReturnedQty}',
                  item.netMovement >= 0 ? '+${item.netMovement}' : '${item.netMovement}',
                ]).toList(),
              ),
              pw.SizedBox(height: 16),
              pw.Divider(),
              pw.Text(
                '${_t('printed_on', lang)}: ${DateFormat.yMMMd().add_jm().format(DateTime.now())}',
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
    'stock_valuation': {'en': 'Stock Valuation', 'ar': 'تقييم المخزون', 'fr': 'Valorisation du Stock'},
    'low_stock': {'en': 'Low Stock Alert', 'ar': 'تنبيه مخزون منخفض', 'fr': 'Alerte Stock Bas'},
    'product_movement': {'en': 'Product Movement', 'ar': 'حركة المنتجات', 'fr': 'Mouvements de Produits'},
    'total_valuation': {'en': 'Total Valuation', 'ar': 'إجمالي التقييم', 'fr': 'Valorisation Totale'},
    'total_stock_units': {'en': 'Total Stock Units', 'ar': 'إجمالي وحدات المخزون', 'fr': 'Unités en Stock'},
    'period': {'en': 'Period', 'ar': 'الفترة', 'fr': 'Période'},
    'sku': {'en': 'SKU', 'ar': 'رمز المنتج', 'fr': 'Réf.'},
    'product': {'en': 'Product', 'ar': 'المنتج', 'fr': 'Produit'},
    'category': {'en': 'Category', 'ar': 'الفئة', 'fr': 'Catégorie'},
    'stock': {'en': 'Stock', 'ar': 'المخزون', 'fr': 'Stock'},
    'unit_cost': {'en': 'Unit Cost', 'ar': 'تكلفة الوحدة', 'fr': 'Coût Unit.'},
    'valuation': {'en': 'Valuation', 'ar': 'التقييم', 'fr': 'Valorisation'},
    'current_stock': {'en': 'Current', 'ar': 'الحالي', 'fr': 'Actuel'},
    'reorder_level': {'en': 'Reorder', 'ar': 'إعادة الطلب', 'fr': 'Seuil'},
    'deficit': {'en': 'Deficit', 'ar': 'العجز', 'fr': 'Déficit'},
    'low_stock_alert': {'en': 'Products below reorder level', 'ar': 'منتجات أقل من مستوى إعادة الطلب', 'fr': 'Produits sous le seuil'},
    'purchased': {'en': 'Purchased', 'ar': 'مشتريات', 'fr': 'Acheté'},
    'sold': {'en': 'Sold', 'ar': 'مبيعات', 'fr': 'Vendu'},
    'returned': {'en': 'Returned', 'ar': 'مرتجعات', 'fr': 'Retourné'},
    'sale_returned': {'en': 'Sale Ret.', 'ar': 'مرتجع بيع', 'fr': 'Ret. Vente'},
    'purchase_returned': {'en': 'Purch. Ret.', 'ar': 'مرتجع شراء', 'fr': 'Ret. Achat'},
    'supplier': {'en': 'Supplier', 'ar': 'المورد', 'fr': 'Fournisseur'},
    'search': {'en': 'Search', 'ar': 'بحث', 'fr': 'Recherche'},
    'net_movement': {'en': 'Net', 'ar': 'الصافي', 'fr': 'Net'},
    'color_size': {'en': 'Color / Size', 'ar': 'اللون / المقاس', 'fr': 'Couleur / Taille'},
    'cost_price': {'en': 'Cost Price', 'ar': 'سعر التكلفة', 'fr': 'Prix Coût'},
    'sale_price': {'en': 'Sale Price', 'ar': 'سعر البيع', 'fr': 'Prix Vente'},
    'wholesale_price': {'en': 'Wholesale', 'ar': 'سعر الجملة', 'fr': 'Prix Gros'},
    'printed_on': {'en': 'Printed on', 'ar': 'طُبع في', 'fr': 'Imprimé le'},
  };

  static String _t(String key, String lang) {
    return _translations[key]?[lang] ?? _translations[key]?['en'] ?? key;
  }

  static String _priceTypeLabel(PriceDisplayType type, String lang) {
    switch (type) {
      case PriceDisplayType.cost:
        return _t('cost_price', lang);
      case PriceDisplayType.sale:
        return _t('sale_price', lang);
      case PriceDisplayType.wholesale:
        return _t('wholesale_price', lang);
    }
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
