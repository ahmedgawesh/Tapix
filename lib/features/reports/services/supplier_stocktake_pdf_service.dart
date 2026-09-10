import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/di/injection_container.dart';
import '../../../core/measurement/measurement_localization.dart';
import '../../../core/services/currency_service.dart';
import '../../settings/data/services/company_profile_service.dart';
import '../../settings/domain/entities/company_profile.dart';
import '../presentation/bloc/supplier_stocktake_report_bloc.dart';

class SupplierStocktakePdfService {
  static Future<void> printSupplierStocktakeReport({
    required BuildContext context,
    required SupplierStocktakeReportData data,
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
          'SupplierStocktakeReport_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> shareSupplierStocktakeReport({
    required BuildContext context,
    required SupplierStocktakeReportData data,
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

    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'SupplierStocktakeReport_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  static Future<pw.Document> _buildPdf({
    required SupplierStocktakeReportData data,
    required CurrencyService cs,
    required Locale locale,
    required bool isRtl,
    required CompanyProfile company,
  }) async {
    final fonts = await _loadFonts();
    final pdf = pw.Document();
    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final lang = locale.languageCode;
    String totalOf(int Function(SupplierStocktakeProductItem item) selector) {
      final totals = <String, int>{};
      for (final item in data.products) {
        totals.update(
          item.measurementType,
          (value) => value + selector(item),
          ifAbsent: () => selector(item),
        );
      }
      return localizedQuantityTotals(totals);
    }

    final dateRangeStr =
        '${DateFormat('dd/MM/yyyy').format(data.dateRange.startDate)} - ${DateFormat('dd/MM/yyyy').format(data.dateRange.endDate)}';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        textDirection: dir,
        build: (pw.Context context) {
          return [
            _buildHeader(
              company,
              _t('supplier_stocktake_report', lang),
              fonts,
              dir,
            ),
            pw.SizedBox(height: 8),

            // Supplier name and date range
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '${_t('supplier', lang)}: ${data.supplierName ?? '-'}',
                  style: pw.TextStyle(font: fonts.bold, fontSize: 12),
                ),
                pw.Text(
                  '${_t('period', lang)}: $dateRangeStr',
                  style: pw.TextStyle(font: fonts.regular, fontSize: 10),
                ),
              ],
            ),
            if (data.supplierPhone != null && data.supplierPhone!.isNotEmpty)
              pw.Text(
                '${_t('phone', lang)}: ${data.supplierPhone}',
                style: pw.TextStyle(
                  font: fonts.regular,
                  fontSize: 9,
                  color: PdfColors.grey600,
                ),
              ),
            pw.SizedBox(height: 8),

            // Filter info
            if (data.searchQuery.isNotEmpty ||
                data.filterCategoryName != null) ...[
              pw.SizedBox(height: 4),
              pw.Text(
                [
                  if (data.filterCategoryName != null)
                    '${_t('category', lang)}: ${data.filterCategoryName}',
                  if (data.searchQuery.isNotEmpty)
                    '${_t('search', lang)}: ${data.searchQuery}',
                ].join('  |  '),
                style: pw.TextStyle(
                  font: fonts.regular,
                  fontSize: 9,
                  color: PdfColors.grey700,
                ),
              ),
            ],
            pw.SizedBox(height: 8),

            // Summary row
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '${_t('total_purchased', lang)}: ${totalOf((item) => item.purchasedQuantity)}',
                  style: pw.TextStyle(font: fonts.bold, fontSize: 9),
                ),
                pw.Text(
                  '${_t('total_sold', lang)}: ${totalOf((item) => item.soldQuantity)}',
                  style: pw.TextStyle(font: fonts.bold, fontSize: 9),
                ),
                pw.Text(
                  '${_t('sale_returned', lang)}: ${totalOf((item) => item.saleReturnedQuantity)}',
                  style: pw.TextStyle(font: fonts.bold, fontSize: 9),
                ),
                pw.Text(
                  '${_t('purchase_returned', lang)}: ${totalOf((item) => item.purchaseReturnedQuantity)}',
                  style: pw.TextStyle(font: fonts.bold, fontSize: 9),
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '${_t('total_remaining', lang)}: ${data.totalRemainingQuantity}',
                  style: pw.TextStyle(font: fonts.bold, fontSize: 9),
                ),
                pw.Text(
                  '${_t('remaining_value', lang)}: ${cs.formatCents(data.totalRemainingValueCents)}',
                  style: pw.TextStyle(font: fonts.bold, fontSize: 9),
                ),
                pw.Text(
                  '${_t('total_profit', lang)}: ${cs.formatCents(data.totalProfitCents)}',
                  style: pw.TextStyle(
                    font: fonts.bold,
                    fontSize: 9,
                    color: data.totalProfitCents >= 0
                        ? PdfColors.teal
                        : PdfColors.red,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '${_t('total_products', lang)}: ${data.totalProducts}',
                  style: pw.TextStyle(font: fonts.regular, fontSize: 9),
                ),
                pw.Text(
                  '${_t('total_variants', lang)}: ${data.totalVariants}',
                  style: pw.TextStyle(font: fonts.regular, fontSize: 9),
                ),
              ],
            ),
            pw.SizedBox(height: 12),

            // Products table
            if (data.products.isNotEmpty)
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 8),
                cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 7),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey100,
                ),
                cellAlignments: {
                  0: pw.Alignment.center,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.centerLeft,
                  3: pw.Alignment.centerLeft,
                  4: pw.Alignment.centerRight,
                  5: pw.Alignment.centerRight,
                  6: pw.Alignment.centerRight,
                  7: pw.Alignment.centerRight,
                  8: pw.Alignment.centerRight,
                  9: pw.Alignment.centerRight,
                  10: pw.Alignment.centerRight,
                  11: pw.Alignment.centerRight,
                },
                headers: [
                  '#',
                  _t('product', lang),
                  _t('sku', lang),
                  _t('variant', lang),
                  _t('purchased', lang),
                  _t('sold', lang),
                  _t('sale_returned', lang),
                  _t('purchase_returned', lang),
                  _t('remaining', lang),
                  _t('unit_cost', lang),
                  _t('remaining_value', lang),
                  _t('profit', lang),
                ],
                data: data.products.asMap().entries.map((entry) {
                  final idx = entry.key + 1;
                  final item = entry.value;
                  return [
                    '$idx',
                    item.productName,
                    item.sku ?? '-',
                    item.variantLabel.isNotEmpty ? item.variantLabel : '-',
                    localizedQuantity(
                      item.purchasedQuantity,
                      item.measurementType,
                    ),
                    localizedQuantity(item.soldQuantity, item.measurementType),
                    localizedQuantity(
                      item.saleReturnedQuantity,
                      item.measurementType,
                    ),
                    localizedQuantity(
                      item.purchaseReturnedQuantity,
                      item.measurementType,
                    ),
                    localizedQuantity(
                      item.remainingQuantity,
                      item.measurementType,
                    ),
                    cs.formatCents(item.costCents),
                    cs.formatCents(item.remainingValueCents),
                    cs.formatCents(item.profitCents),
                  ];
                }).toList(),
              ),

            pw.SizedBox(height: 8),

            // Grand total footer
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    _t('grand_total', lang),
                    style: pw.TextStyle(font: fonts.bold, fontSize: 11),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        '${_t('purchased', lang)}: ${totalOf((item) => item.purchasedQuantity)}',
                        style: pw.TextStyle(font: fonts.regular, fontSize: 8),
                      ),
                      pw.Text(
                        '${_t('sold', lang)}: ${totalOf((item) => item.soldQuantity)}',
                        style: pw.TextStyle(font: fonts.regular, fontSize: 8),
                      ),
                      pw.Text(
                        '${_t('sale_returned', lang)}: ${data.totalSaleReturnedQuantity}',
                        style: pw.TextStyle(font: fonts.regular, fontSize: 8),
                      ),
                      pw.Text(
                        '${_t('purchase_returned', lang)}: ${data.totalPurchaseReturnedQuantity}',
                        style: pw.TextStyle(font: fonts.regular, fontSize: 8),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 2),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        '${_t('remaining', lang)}: ${data.totalRemainingQuantity}',
                        style: pw.TextStyle(font: fonts.bold, fontSize: 9),
                      ),
                      pw.Text(
                        '${_t('remaining_value', lang)}: ${cs.formatCents(data.totalRemainingValueCents)}',
                        style: pw.TextStyle(font: fonts.bold, fontSize: 9),
                      ),
                      pw.Text(
                        '${_t('total_profit', lang)}: ${cs.formatCents(data.totalProfitCents)}',
                        style: pw.TextStyle(
                          font: fonts.bold,
                          fontSize: 9,
                          color: data.totalProfitCents >= 0
                              ? PdfColors.teal
                              : PdfColors.red,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 16),
            pw.Divider(),
            pw.Text(
              '${_t('printed_on', lang)}: ${DateFormat('dd/MM/yyyy').add_jm().format(DateTime.now())}',
              style: pw.TextStyle(
                font: fonts.regular,
                fontSize: 8,
                color: PdfColors.grey600,
              ),
            ),
          ];
        },
      ),
    );

    return pdf;
  }

  // ═══════════════════════════════════════════════════════
  // 3-LANGUAGE TRANSLATIONS FOR PDF
  // ═══════════════════════════════════════════════════════

  static const _translations = {
    'supplier_stocktake_report': {
      'en': 'Supplier Stocktake Report',
      'ar': 'تقرير جرد المخزون حسب المورد',
      'fr': 'Rapport d\'Inventaire par Fournisseur',
    },
    'supplier': {'en': 'Supplier', 'ar': 'المورد', 'fr': 'Fournisseur'},
    'period': {'en': 'Period', 'ar': 'الفترة', 'fr': 'Période'},
    'phone': {'en': 'Phone', 'ar': 'الهاتف', 'fr': 'Téléphone'},
    'category': {'en': 'Category', 'ar': 'التصنيف', 'fr': 'Catégorie'},
    'search': {'en': 'Search', 'ar': 'بحث', 'fr': 'Recherche'},
    'total_purchased': {
      'en': 'Total Purchased',
      'ar': 'إجمالي المشتريات',
      'fr': 'Total Acheté',
    },
    'total_sold': {
      'en': 'Total Sold',
      'ar': 'إجمالي المبيعات',
      'fr': 'Total Vendu',
    },
    'sale_returned': {'en': 'Sale Ret.', 'ar': 'مرتجع بيع', 'fr': 'Ret. Vente'},
    'purchase_returned': {
      'en': 'Purch. Ret.',
      'ar': 'مرتجع شراء',
      'fr': 'Ret. Achat',
    },
    'total_remaining': {
      'en': 'Total Remaining',
      'ar': 'إجمالي المتبقي',
      'fr': 'Total Restant',
    },
    'remaining_value': {
      'en': 'Remaining Value',
      'ar': 'قيمة المتبقي',
      'fr': 'Valeur Restante',
    },
    'total_profit': {
      'en': 'Total Profit',
      'ar': 'إجمالي الأرباح',
      'fr': 'Profit Total',
    },
    'profit': {'en': 'Profit', 'ar': 'الربح', 'fr': 'Profit'},
    'total_products': {
      'en': 'Total Products',
      'ar': 'إجمالي المنتجات',
      'fr': 'Total Produits',
    },
    'total_variants': {
      'en': 'Total Variants',
      'ar': 'إجمالي المتغيرات',
      'fr': 'Total Variantes',
    },
    'product': {'en': 'Product', 'ar': 'المنتج', 'fr': 'Produit'},
    'sku': {'en': 'SKU', 'ar': 'رمز المنتج', 'fr': 'SKU'},
    'variant': {'en': 'Variant', 'ar': 'المتغير', 'fr': 'Variante'},
    'purchased': {'en': 'Purchased', 'ar': 'المشتراة', 'fr': 'Acheté'},
    'sold': {'en': 'Sold', 'ar': 'المباعة', 'fr': 'Vendu'},
    'remaining': {'en': 'Remaining', 'ar': 'المتبقي', 'fr': 'Restant'},
    'unit_cost': {
      'en': 'Unit Cost',
      'ar': 'تكلفة الوحدة',
      'fr': 'Coût Unitaire',
    },
    'grand_total': {
      'en': 'Grand Total',
      'ar': 'المجموع الكلي',
      'fr': 'Total Général',
    },
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
}

class _PdfFonts {
  final pw.Font regular;
  final pw.Font bold;

  _PdfFonts({required this.regular, required this.bold});
}
