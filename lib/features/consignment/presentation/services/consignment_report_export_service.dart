import 'package:easy_localization/easy_localization.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/measurement/measurement_localization.dart';
import '../../../../core/services/currency_service.dart';
import '../../../settings/data/services/company_profile_service.dart';
import '../../data/consignment_reporting_service.dart';

class ConsignmentReportExportService {
  const ConsignmentReportExportService._();

  static List<String> get _headers => [
    'supplier',
    'currency',
    'received_qty',
    'gross_sold_qty',
    'returned_qty',
    'net_sold_qty',
    'remaining_qty',
    'unavailable_qty',
    'period_obligation',
    'settled_in_period',
    'paid_in_period',
    'closing_unsettled',
    'closing_payable',
  ].map((key) => 'consignment.$key'.tr()).toList();

  static List<String> _cells(ConsignmentSupplierReportRow row) => [
    row.supplierName,
    row.currencyCode,
    localizedQuantityTotals(row.receivedQuantities),
    localizedQuantityTotals(row.grossSoldQuantities),
    localizedQuantityTotals(row.returnedQuantities),
    localizedQuantityTotals(row.netSoldQuantities),
    localizedQuantityTotals(row.remainingQuantities),
    localizedQuantityTotals(row.unavailableQuantities),
    _money(row.periodObligationCents, row.currencyCode),
    _money(row.postedSettlementCents, row.currencyCode),
    _money(row.paidCents, row.currencyCode),
    _money(row.unsettledObligationCents, row.currencyCode),
    _money(row.outstandingPayableCents, row.currencyCode),
  ];

  static String _money(int value, String code) =>
      sl<CurrencyService>().formatForCode(value, code);

  static Future<void> export(
    BuildContext context, {
    required List<ConsignmentSupplierReportRow> rows,
    required ConsignmentReportRange range,
    required String supplierLabel,
    bool excel = false,
    bool share = false,
  }) async {
    final rtl = context.locale.languageCode == 'ar';
    final renderBox = context.findRenderObject() as RenderBox?;
    final origin = renderBox == null
        ? null
        : renderBox.localToGlobal(Offset.zero) & renderBox.size;
    final profile = await sl<CompanyProfileService>().getProfile();
    final title = 'consignment.report_title'.tr();
    final dates =
        '${DateFormat('yyyy-MM-dd').format(range.start.toLocal())} — '
        '${DateFormat('yyyy-MM-dd').format(range.end.toLocal())}';
    final caption = '$dates • ${'consignment.supplier'.tr()}: $supplierLabel';
    final note = 'consignment.period_balance_note'.tr();

    if (excel) {
      final book = Excel.createExcel();
      final sheet = book['Consignment'];
      book.delete('Sheet1');
      for (final text in [profile.name, title, caption, note]) {
        sheet.appendRow([TextCellValue(text)]);
      }
      sheet.appendRow(_headers.map(TextCellValue.new).toList());
      if (rows.isEmpty) {
        sheet.appendRow([TextCellValue('consignment.empty'.tr())]);
      }
      for (final row in rows) {
        sheet.appendRow(_cells(row).map(TextCellValue.new).toList());
      }
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              Uint8List.fromList(book.save()!),
              name: 'ConsignmentReport.xlsx',
              mimeType:
                  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            ),
          ],
          subject: title,
          sharePositionOrigin: origin,
        ),
      );
      return;
    }

    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/IBMPlexSansArabic-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/IBMPlexSansArabic-Bold.ttf'),
    );
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        theme: pw.ThemeData.withFont(base: font, bold: bold),
        textDirection: rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        build: (_) => [
          pw.Text(profile.name),
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(caption, style: const pw.TextStyle(fontSize: 9)),
          pw.Text(note, style: const pw.TextStyle(fontSize: 9)),
          pw.SizedBox(height: 12),
          if (rows.isEmpty) pw.Text('consignment.empty'.tr()),
          pw.TableHelper.fromTextArray(
            headers: _headers,
            data: rows.map(_cells).toList(),
            cellStyle: const pw.TextStyle(fontSize: 6.5),
            headerStyle: pw.TextStyle(
              fontSize: 7,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
    if (share) {
      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename: 'ConsignmentReport.pdf',
      );
    } else {
      await Printing.layoutPdf(onLayout: (_) => pdf.save(), name: title);
    }
  }
}
