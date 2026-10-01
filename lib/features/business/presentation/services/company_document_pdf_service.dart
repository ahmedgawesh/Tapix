import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../data/company_branch_monitor_service.dart';

class CompanyDocumentPdfService {
  const CompanyDocumentPdfService._();

  static Future<void> printDocument({
    required CompanyDocumentSnapshot document,
    required String languageCode,
  }) async {
    final pdf = await _build(document, languageCode);
    await Printing.layoutPdf(
      name: _fileName(document),
      onLayout: (_) => pdf.save(),
    );
  }

  static Future<void> shareDocument({
    required CompanyDocumentSnapshot document,
    required String languageCode,
  }) async {
    final pdf = await _build(document, languageCode);
    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: '${_fileName(document)}.pdf',
    );
  }

  static Future<pw.Document> _build(
    CompanyDocumentSnapshot document,
    String languageCode,
  ) async {
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/IBMPlexSansArabic-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/IBMPlexSansArabic-Bold.ttf'),
    );
    final labels = _labels(languageCode);
    final pdf = pw.Document();
    final direction = languageCode == 'ar'
        ? pw.TextDirection.rtl
        : pw.TextDirection.ltr;
    String amount(int value) =>
        '${document.currencyCode} ${(value / 100).toStringAsFixed(2)}';
    String breakdown(int value) =>
        document.hasFinancialBreakdown ? amount(value) : labels['unavailable']!;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: direction,
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        margin: const pw.EdgeInsets.all(28),
        header: (_) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              labels['title']!,
              style: pw.TextStyle(font: bold, fontSize: 18),
            ),
            pw.Text(document.number, textDirection: pw.TextDirection.ltr),
          ],
        ),
        build: (_) => [
          pw.Divider(),
          pw.SizedBox(height: 10),
          pw.Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              _fact(labels['type']!, _kind(document.kind, languageCode), bold),
              _fact(
                labels['status']!,
                document.isVoided ? labels['voided']! : labels['posted']!,
                bold,
              ),
              _fact(
                labels['date']!,
                DateFormat(
                  'yyyy-MM-dd HH:mm',
                ).format(document.documentDate.toLocal()),
                bold,
              ),
              _fact(labels['branch']!, document.branchName, bold),
              _fact(labels['warehouse']!, document.warehouseName, bold),
              if (document.partyName != null)
                _fact(labels['party']!, document.partyName!, bold),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(font: bold),
            cellStyle: pw.TextStyle(font: regular, fontSize: 9),
            headers: [
              labels['subtotal']!,
              labels['discount']!,
              labels['tax']!,
              labels['paid']!,
              labels['total']!,
            ],
            data: [
              [
                breakdown(document.subtotalMinor),
                breakdown(document.discountMinor),
                breakdown(document.taxMinor),
                breakdown(document.paidMinor),
                amount(document.totalMinor),
              ],
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Text(
            '${labels['items']} (${document.itemCount})',
            style: pw.TextStyle(font: bold, fontSize: 14),
          ),
          pw.SizedBox(height: 8),
          if (document.lines.isEmpty)
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(12),
              color: PdfColors.grey200,
              child: pw.Text(labels['legacy']!),
            )
          else
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(font: bold),
              cellStyle: pw.TextStyle(font: regular, fontSize: 8),
              headers: [
                '#',
                labels['product']!,
                labels['variant']!,
                labels['quantity']!,
                labels['unit']!,
                labels['lineTotal']!,
              ],
              data: [
                for (var i = 0; i < document.lines.length; i++)
                  [
                    (i + 1).toString(),
                    document.lines[i].productName,
                    document.lines[i].variantName ?? '—',
                    _quantity(document.lines[i]),
                    amount(document.lines[i].unitMinor),
                    amount(document.lines[i].totalMinor),
                  ],
              ],
            ),
          if (document.notes?.trim().isNotEmpty == true) ...[
            pw.SizedBox(height: 14),
            pw.Text(
              '${labels['notes']}: ${document.notes!.trim()}',
              style: pw.TextStyle(font: regular),
            ),
          ],
          pw.SizedBox(height: 18),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(10),
            color: PdfColors.grey100,
            child: pw.Text(
              document.isRemote
                  ? labels['remoteEvidence']!
                  : labels['localEvidence']!,
              style: pw.TextStyle(font: regular, fontSize: 8),
            ),
          ),
        ],
      ),
    );
    return pdf;
  }

  static pw.Widget _fact(String label, String value, pw.Font bold) =>
      pw.SizedBox(
        width: 235,
        child: pw.Row(
          children: [
            pw.Text('$label: ', style: pw.TextStyle(font: bold)),
            pw.Expanded(child: pw.Text(value)),
          ],
        ),
      );

  static String _quantity(CompanyDocumentLineSnapshot line) {
    final value = line.quantityScaled / line.quantityScale;
    final formatted = value == value.truncateToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(3);
    return '$formatted ${line.measurementType}';
  }

  static String _fileName(CompanyDocumentSnapshot document) =>
      'Tapix_${document.number.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}';

  static String _kind(CompanyDocumentKind kind, String languageCode) {
    final ar = languageCode == 'ar';
    final fr = languageCode == 'fr';
    return switch (kind) {
      CompanyDocumentKind.purchase =>
        ar
            ? 'شراء'
            : fr
            ? 'Achat'
            : 'Purchase',
      CompanyDocumentKind.sale =>
        ar
            ? 'بيع'
            : fr
            ? 'Vente'
            : 'Sale',
      CompanyDocumentKind.purchaseReturn =>
        ar
            ? 'مرتجع مشتريات'
            : fr
            ? 'Retour achat'
            : 'Purchase return',
      CompanyDocumentKind.saleReturn =>
        ar
            ? 'مرتجع مبيعات'
            : fr
            ? 'Retour vente'
            : 'Sale return',
      CompanyDocumentKind.purchaseAdjustmentReturn =>
        ar
            ? 'مرتجع تسوية مشتريات'
            : fr
            ? 'Ajustement retour achat'
            : 'Purchase adjustment return',
      CompanyDocumentKind.saleAdjustmentReturn =>
        ar
            ? 'مرتجع تسوية مبيعات'
            : fr
            ? 'Ajustement retour vente'
            : 'Sale adjustment return',
    };
  }

  static Map<String, String> _labels(String languageCode) {
    if (languageCode == 'ar') {
      return {
        'title': 'تفاصيل المستند',
        'type': 'النوع',
        'status': 'الحالة',
        'posted': 'مرحل',
        'voided': 'ملغي',
        'date': 'التاريخ',
        'branch': 'الفرع',
        'warehouse': 'المخزن',
        'party': 'الطرف',
        'subtotal': 'المجموع الفرعي',
        'discount': 'الخصم',
        'tax': 'الضريبة',
        'paid': 'المدفوع',
        'total': 'الإجمالي',
        'items': 'بنود المستند',
        'product': 'الصنف',
        'variant': 'المتغير',
        'quantity': 'الكمية',
        'unit': 'سعر الوحدة',
        'lineTotal': 'إجمالي البند',
        'notes': 'ملاحظات',
        'unavailable': 'غير متاح في الإصدار القديم',
        'legacy': 'وصل هذا المستند من إصدار قديم دون تفاصيل البنود.',
        'remoteEvidence':
            'لقطة قراءة من دفتر الفرع المصدر؛ لا ينشئ عرضها قيدًا محاسبيًا مكررًا.',
        'localEvidence': 'لقطة قراءة من دفتر هذا الجهاز.',
      };
    }
    if (languageCode == 'fr') {
      return {
        'title': 'Détails du document',
        'type': 'Type',
        'status': 'Statut',
        'posted': 'Validé',
        'voided': 'Annulé',
        'date': 'Date',
        'branch': 'Succursale',
        'warehouse': 'Entrepôt',
        'party': 'Tiers',
        'subtotal': 'Sous-total',
        'discount': 'Remise',
        'tax': 'Taxe',
        'paid': 'Payé',
        'total': 'Total',
        'items': 'Lignes',
        'product': 'Produit',
        'variant': 'Variante',
        'quantity': 'Quantité',
        'unit': 'Prix unitaire',
        'lineTotal': 'Total ligne',
        'notes': 'Notes',
        'unavailable': 'Indisponible dans l’ancienne version',
        'legacy': 'Ce document ancien ne contient pas le détail des lignes.',
        'remoteEvidence':
            'Vue du registre de la succursale source, sans écriture comptable dupliquée.',
        'localEvidence': 'Vue du registre de cet appareil.',
      };
    }
    return {
      'title': 'Document details',
      'type': 'Type',
      'status': 'Status',
      'posted': 'Posted',
      'voided': 'Voided',
      'date': 'Date',
      'branch': 'Branch',
      'warehouse': 'Warehouse',
      'party': 'Party',
      'subtotal': 'Subtotal',
      'discount': 'Discount',
      'tax': 'Tax',
      'paid': 'Paid',
      'total': 'Total',
      'items': 'Document lines',
      'product': 'Product',
      'variant': 'Variant',
      'quantity': 'Quantity',
      'unit': 'Unit price',
      'lineTotal': 'Line total',
      'notes': 'Notes',
      'unavailable': 'Unavailable in the legacy version',
      'legacy': 'This legacy document did not include line details.',
      'remoteEvidence':
          'Read-only snapshot from the source branch ledger; no duplicate journal is posted.',
      'localEvidence': 'Read-only snapshot from this device ledger.',
    };
  }
}
