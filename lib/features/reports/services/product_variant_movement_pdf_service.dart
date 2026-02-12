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
import '../presentation/bloc/product_variant_movement_bloc.dart';

class ProductVariantMovementPdfService {
  static Future<void> printReport({
    required BuildContext context,
    required ProductVariantMovementData data,
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
      name: 'VariantMovement_${data.selectedProductName ?? ""}_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> shareReport({
    required BuildContext context,
    required ProductVariantMovementData data,
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
      filename: 'VariantMovement_${data.selectedProductName ?? ""}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  static Future<pw.Document> _buildPdf({
    required ProductVariantMovementData data,
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
            _buildHeader(company, _t('title', lang), fonts, dir),
            pw.SizedBox(height: 8),

            // Product info
            pw.Text(
              '${_t('product', lang)}: ${data.selectedProductName ?? "-"}',
              style: pw.TextStyle(font: fonts.bold, fontSize: 12),
            ),
            if (data.selectedProductCategory != null)
              pw.Text(
                '${_t('category', lang)}: ${data.selectedProductCategory}',
                style: pw.TextStyle(font: fonts.regular, fontSize: 10, color: PdfColors.grey600),
              ),
            pw.Text(
              '${_t('type', lang)}: ${data.selectedProductHasVariants ? _t('with_variants', lang) : _t('without_variants', lang)}',
              style: pw.TextStyle(font: fonts.regular, fontSize: 10, color: PdfColors.grey600),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              '${_t('period', lang)}: ${DateFormat.yMMMd().format(data.dateRange.startDate)} — ${DateFormat.yMMMd().format(data.dateRange.endDate)}',
              style: pw.TextStyle(font: fonts.regular, fontSize: 10),
            ),
            pw.SizedBox(height: 12),

            // Summary table
            _buildSummaryTable(data.totals, cs, fonts, lang),
            pw.SizedBox(height: 16),

            // Variant breakdown (if has variants)
            if (data.selectedProductHasVariants && data.variantSummaries.isNotEmpty) ...[
              pw.Text(
                _t('variant_breakdown', lang),
                style: pw.TextStyle(font: fonts.bold, fontSize: 11),
              ),
              pw.SizedBox(height: 8),
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 8),
                cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 8),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.purple50),
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerRight,
                  2: pw.Alignment.centerRight,
                  3: pw.Alignment.centerRight,
                  4: pw.Alignment.centerRight,
                  5: pw.Alignment.centerRight,
                },
                headers: [
                  _t('variant', lang),
                  _t('purchased', lang),
                  _t('sold', lang),
                  _t('sale_returns', lang),
                  _t('purchase_returns', lang),
                  _t('net', lang),
                ],
                data: data.variantSummaries.map((s) => [
                  s.label,
                  '+${s.purchasedQty}',
                  '-${s.soldQty}',
                  '+${s.saleReturnedQty}',
                  '-${s.purchaseReturnedQty}',
                  s.netQty >= 0 ? '+${s.netQty}' : '${s.netQty}',
                ]).toList(),
              ),
              pw.SizedBox(height: 16),
            ],

            // Movement details table
            if (data.movements.isNotEmpty) ...[
              pw.Text(
                _t('movement_details', lang),
                style: pw.TextStyle(font: fonts.bold, fontSize: 11),
              ),
              pw.SizedBox(height: 8),
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 7),
                cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 7),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
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
                  _t('date', lang),
                  _t('type_col', lang),
                  _t('reference', lang),
                  _t('counterparty', lang),
                  _t('variant', lang),
                  _t('qty', lang),
                  _t('amount', lang),
                ],
                data: data.movements.map((m) {
                  final (typeLabel, sign) = _movementTypeInfo(m.type, lang);
                  return [
                    DateFormat.yMd().format(m.date),
                    typeLabel,
                    m.reference,
                    m.counterpartyName ?? '-',
                    m.variantLabel.isNotEmpty ? m.variantLabel : '-',
                    '$sign${m.quantity}',
                    cs.formatCents(m.totalCents),
                  ];
                }).toList(),
              ),
            ],

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

    return pdf;
  }

  static pw.Widget _buildSummaryTable(
    VariantMovementTotals totals,
    CurrencyService cs,
    _PdfFonts fonts,
    String lang,
  ) {
    return pw.TableHelper.fromTextArray(
      headerStyle: pw.TextStyle(font: fonts.bold, fontSize: 9),
      cellStyle: pw.TextStyle(font: fonts.regular, fontSize: 9),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blue50),
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerRight,
        2: pw.Alignment.centerRight,
      },
      headers: [
        _t('movement_type', lang),
        _t('qty', lang),
        _t('amount', lang),
      ],
      data: [
        [_t('purchases', lang), '+${totals.totalPurchased}', cs.formatCents(totals.totalPurchaseCents)],
        [_t('sales', lang), '-${totals.totalSold}', cs.formatCents(totals.totalSalesCents)],
        [_t('sale_returns', lang), '+${totals.totalSaleReturned}', cs.formatCents(totals.totalSaleReturnCents)],
        [_t('purchase_returns', lang), '-${totals.totalPurchaseReturned}', cs.formatCents(totals.totalPurchaseReturnCents)],
        [
          _t('net', lang),
          totals.netQuantity >= 0 ? '+${totals.netQuantity}' : '${totals.netQuantity}',
          '',
        ],
      ],
    );
  }

  static (String, String) _movementTypeInfo(VariantMovementType type, String lang) {
    switch (type) {
      case VariantMovementType.purchase:
        return (_t('purchases', lang), '+');
      case VariantMovementType.sale:
        return (_t('sales', lang), '-');
      case VariantMovementType.saleReturn:
        return (_t('sale_returns', lang), '+');
      case VariantMovementType.purchaseReturn:
        return (_t('purchase_returns', lang), '-');
    }
  }

  // ═══════════════════════════════════════════════════════
  // 3-LANGUAGE TRANSLATIONS FOR PDF
  // ═══════════════════════════════════════════════════════

  static const _translations = {
    'title': {'en': 'Product Variant Movement Report', 'ar': 'تقرير حركة متغيرات المنتج', 'fr': 'Rapport Mouvement Variantes Produit'},
    'product': {'en': 'Product', 'ar': 'المنتج', 'fr': 'Produit'},
    'category': {'en': 'Category', 'ar': 'التصنيف', 'fr': 'Catégorie'},
    'type': {'en': 'Type', 'ar': 'النوع', 'fr': 'Type'},
    'with_variants': {'en': 'With Variants', 'ar': 'مع متغيرات', 'fr': 'Avec Variantes'},
    'without_variants': {'en': 'Without Variants', 'ar': 'بدون متغيرات', 'fr': 'Sans Variantes'},
    'period': {'en': 'Period', 'ar': 'الفترة', 'fr': 'Période'},
    'variant_breakdown': {'en': 'Variant Breakdown', 'ar': 'تفصيل المتغيرات', 'fr': 'Détail des Variantes'},
    'movement_details': {'en': 'Movement Details', 'ar': 'تفاصيل الحركة', 'fr': 'Détails des Mouvements'},
    'movement_type': {'en': 'Movement Type', 'ar': 'نوع الحركة', 'fr': 'Type de Mouvement'},
    'date': {'en': 'Date', 'ar': 'التاريخ', 'fr': 'Date'},
    'type_col': {'en': 'Type', 'ar': 'النوع', 'fr': 'Type'},
    'reference': {'en': 'Reference', 'ar': 'المرجع', 'fr': 'Référence'},
    'counterparty': {'en': 'Supplier / Customer', 'ar': 'المورد / العميل', 'fr': 'Fournisseur / Client'},
    'variant': {'en': 'Variant', 'ar': 'المتغير', 'fr': 'Variante'},
    'qty': {'en': 'Qty', 'ar': 'الكمية', 'fr': 'Qté'},
    'amount': {'en': 'Amount', 'ar': 'المبلغ', 'fr': 'Montant'},
    'purchased': {'en': 'Purchased', 'ar': 'مشتريات', 'fr': 'Achats'},
    'sold': {'en': 'Sold', 'ar': 'مبيعات', 'fr': 'Ventes'},
    'purchases': {'en': 'Purchases', 'ar': 'مشتريات', 'fr': 'Achats'},
    'sales': {'en': 'Sales', 'ar': 'مبيعات', 'fr': 'Ventes'},
    'sale_returns': {'en': 'Sale Returns', 'ar': 'مرتجعات مبيعات', 'fr': 'Retours Ventes'},
    'purchase_returns': {'en': 'Purchase Returns', 'ar': 'مرتجعات مشتريات', 'fr': 'Retours Achats'},
    'net': {'en': 'Net Movement', 'ar': 'صافي الحركة', 'fr': 'Mouvement Net'},
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
