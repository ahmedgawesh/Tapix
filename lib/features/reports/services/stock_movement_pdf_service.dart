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
import '../presentation/bloc/stock_movement_report_bloc.dart';

class StockMovementPdfService {
  static Future<void> printReport({
    required BuildContext context,
    required StockMovementReportData data,
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
      name: 'StockMovement_${data.selectedProductName ?? ""}_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
  }

  static Future<void> shareReport({
    required BuildContext context,
    required StockMovementReportData data,
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
      filename: 'StockMovement_${data.selectedProductName ?? ""}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  static Future<pw.Document> _buildPdf({
    required StockMovementReportData data,
    required CurrencyService cs,
    required Locale locale,
    required bool isRtl,
    required CompanyProfile company,
  }) async {
    final fonts = await _loadFonts();
    final pdf = pw.Document();
    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final lang = locale.languageCode;
    final filtered = data.filteredMovements;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: dir,
        build: (pw.Context context) {
          return [
            // Header
            _buildHeader(company, _t('title', lang), fonts, dir),
            pw.SizedBox(height: 8),

            // Product name
            pw.Text(
              '${_t('product', lang)}: ${data.selectedProductName ?? "-"}',
              style: pw.TextStyle(font: fonts.bold, fontSize: 12),
            ),
            pw.SizedBox(height: 4),

            // Period
            pw.Text(
              '${_t('period', lang)}: ${DateFormat.yMMMd().format(data.dateRange.startDate)} — ${DateFormat.yMMMd().format(data.dateRange.endDate)}',
              style: pw.TextStyle(font: fonts.regular, fontSize: 10),
            ),
            pw.SizedBox(height: 12),

            // Summary table
            _buildSummaryTable(data.summary, cs, fonts, lang),
            pw.SizedBox(height: 16),

            // Movement details table
            if (filtered.isNotEmpty) ...[
              pw.Text(
                _t('movement_details', lang),
                style: pw.TextStyle(font: fonts.bold, fontSize: 11),
              ),
              pw.SizedBox(height: 8),
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
                },
                headers: [
                  _t('date', lang),
                  _t('type', lang),
                  _t('reference', lang),
                  _t('counterparty', lang),
                  _t('quantity', lang),
                  _t('amount', lang),
                ],
                data: filtered.map((m) {
                  final (typeLabel, sign) = _movementTypeInfo(m.type, lang);
                  return [
                    DateFormat.yMd().format(m.date),
                    typeLabel,
                    m.reference,
                    m.counterpartyName ?? '-',
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
    StockMovementSummary summary,
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
        _t('quantity', lang),
        _t('amount', lang),
      ],
      data: [
        [_t('purchases', lang), '+${summary.totalPurchased}', cs.formatCents(summary.totalPurchaseCents)],
        [_t('sales', lang), '-${summary.totalSold}', cs.formatCents(summary.totalSalesCents)],
        [_t('sale_returns_linked', lang), '+${summary.totalSaleReturned}', cs.formatCents(summary.totalSaleReturnCents)],
        [_t('sale_returns_unlinked', lang), '+${summary.totalSaleReturnAdj}', cs.formatCents(summary.totalSaleReturnAdjCents)],
        [_t('purchase_returns_linked', lang), '-${summary.totalPurchaseReturned}', cs.formatCents(summary.totalPurchaseReturnCents)],
        [_t('purchase_returns_unlinked', lang), '-${summary.totalPurchaseReturnAdj}', cs.formatCents(summary.totalPurchaseReturnAdjCents)],
        [
          _t('net_movement', lang),
          summary.netQuantity >= 0 ? '+${summary.netQuantity}' : '${summary.netQuantity}',
          '',
        ],
      ],
    );
  }

  static (String, String) _movementTypeInfo(StockMovementType type, String lang) {
    switch (type) {
      case StockMovementType.purchase:
        return (_t('purchases', lang), '+');
      case StockMovementType.sale:
        return (_t('sales', lang), '-');
      case StockMovementType.saleReturn:
        return (_t('sale_returns_linked', lang), '+');
      case StockMovementType.saleReturnAdjustment:
        return (_t('sale_returns_unlinked', lang), '+');
      case StockMovementType.purchaseReturn:
        return (_t('purchase_returns_linked', lang), '-');
      case StockMovementType.purchaseReturnAdjustment:
        return (_t('purchase_returns_unlinked', lang), '-');
    }
  }

  // ═══════════════════════════════════════════════════════
  // 3-LANGUAGE TRANSLATIONS FOR PDF
  // ═══════════════════════════════════════════════════════

  static const _translations = {
    'title': {'en': 'Stock Movement Report', 'ar': 'تقرير حركات المخزون الشامل', 'fr': 'Rapport de Mouvement de Stock'},
    'product': {'en': 'Product', 'ar': 'المنتج', 'fr': 'Produit'},
    'period': {'en': 'Period', 'ar': 'الفترة', 'fr': 'Période'},
    'movement_details': {'en': 'Movement Details', 'ar': 'تفاصيل الحركة', 'fr': 'Détails des Mouvements'},
    'movement_type': {'en': 'Movement Type', 'ar': 'نوع الحركة', 'fr': 'Type de Mouvement'},
    'date': {'en': 'Date', 'ar': 'التاريخ', 'fr': 'Date'},
    'type': {'en': 'Type', 'ar': 'النوع', 'fr': 'Type'},
    'reference': {'en': 'Reference', 'ar': 'المرجع', 'fr': 'Référence'},
    'counterparty': {'en': 'Supplier / Customer', 'ar': 'المورد / العميل', 'fr': 'Fournisseur / Client'},
    'quantity': {'en': 'Qty', 'ar': 'الكمية', 'fr': 'Qté'},
    'amount': {'en': 'Amount', 'ar': 'المبلغ', 'fr': 'Montant'},
    'purchases': {'en': 'Purchases', 'ar': 'مشتريات', 'fr': 'Achats'},
    'sales': {'en': 'Sales', 'ar': 'مبيعات', 'fr': 'Ventes'},
    'sale_returns_linked': {'en': 'Sale Returns (Linked)', 'ar': 'مرتجعات بيع (مرتبطة)', 'fr': 'Retours Ventes (Liés)'},
    'sale_returns_unlinked': {'en': 'Sale Returns (Adjustment)', 'ar': 'مرتجعات بيع (غير مرتبطة)', 'fr': 'Retours Ventes (Ajustement)'},
    'purchase_returns_linked': {'en': 'Purchase Returns (Linked)', 'ar': 'مرتجعات شراء (مرتبطة)', 'fr': 'Retours Achats (Liés)'},
    'purchase_returns_unlinked': {'en': 'Purchase Returns (Adjustment)', 'ar': 'مرتجعات شراء (غير مرتبطة)', 'fr': 'Retours Achats (Ajustement)'},
    'net_movement': {'en': 'Net Movement', 'ar': 'صافي الحركة', 'fr': 'Mouvement Net'},
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
