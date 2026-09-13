import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/di/injection_container.dart';
import '../../settings/data/services/company_profile_service.dart';
import 'unapplied_advances_report_service.dart';

class UnappliedAdvancesExportService {
  static Future<void> printPdf({
    required BuildContext context,
    required List<UnappliedAdvanceReportRow> rows,
    required List<UnappliedAdvanceCurrencySummary> summaries,
  }) async {
    final document = await _buildPdf(context, rows, summaries);
    await Printing.layoutPdf(
      name: _filename('pdf'),
      onLayout: (_) => document.save(),
    );
  }

  static Future<void> sharePdf({
    required BuildContext context,
    required List<UnappliedAdvanceReportRow> rows,
    required List<UnappliedAdvanceCurrencySummary> summaries,
  }) async {
    final document = await _buildPdf(context, rows, summaries);
    await Printing.sharePdf(
      bytes: await document.save(),
      filename: _filename('pdf'),
    );
  }

  static Future<void> shareExcel({
    required BuildContext context,
    required List<UnappliedAdvanceReportRow> rows,
    required List<UnappliedAdvanceCurrencySummary> summaries,
  }) async {
    final excel = Excel.createExcel();
    final details = excel['Unapplied Advances'];
    excel.delete('Sheet1');
    details.appendRow([
      TextCellValue('reports.advance_party_type'.tr()),
      TextCellValue('reports.advance_party'.tr()),
      TextCellValue('reports.advance_cheque_number'.tr()),
      TextCellValue('reports.advance_recognized_date'.tr()),
      TextCellValue('reports.advance_currency'.tr()),
      TextCellValue('reports.advance_original_amount'.tr()),
      TextCellValue('reports.advance_applied_amount'.tr()),
      TextCellValue('reports.advance_unapplied_amount'.tr()),
    ]);
    for (final row in rows) {
      details.appendRow([
        TextCellValue(_partyTypeLabel(row.partyType)),
        TextCellValue(row.partyName),
        TextCellValue(row.chequeNumber),
        TextCellValue(DateFormat('dd/MM/yyyy').format(row.recognizedAt)),
        TextCellValue(row.currencyCode),
        DoubleCellValue(row.amountCents / 100),
        DoubleCellValue(row.appliedCents / 100),
        DoubleCellValue(row.unappliedCents / 100),
      ]);
    }

    final totals = excel['Summary'];
    totals.appendRow([
      TextCellValue('reports.advance_currency'.tr()),
      TextCellValue('reports.customer_advances'.tr()),
      TextCellValue('reports.supplier_advances'.tr()),
    ]);
    for (final summary in summaries) {
      totals.appendRow([
        TextCellValue(summary.currencyCode),
        DoubleCellValue(summary.customerCents / 100),
        DoubleCellValue(summary.supplierCents / 100),
      ]);
    }

    final bytes = excel.save();
    if (bytes == null) return;
    final filename = _filename('xlsx');
    final file = XFile.fromData(
      Uint8List.fromList(bytes),
      name: filename,
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    await SharePlus.instance.share(
      ShareParams(
        files: [file],
        subject: 'reports.unapplied_advances_report'.tr(),
      ),
    );
  }

  static Future<pw.Document> _buildPdf(
    BuildContext context,
    List<UnappliedAdvanceReportRow> rows,
    List<UnappliedAdvanceCurrencySummary> summaries,
  ) async {
    final locale = context.locale;
    final rtl = locale.languageCode == 'ar';
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/IBMPlexSansArabic-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/IBMPlexSansArabic-Bold.ttf'),
    );
    final company = await sl<CompanyProfileService>().getProfile();
    final document = pw.Document();
    final headerStyle = pw.TextStyle(
      font: bold,
      fontSize: 8,
      color: PdfColors.white,
    );
    final cellStyle = pw.TextStyle(font: regular, fontSize: 8);

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        textDirection: rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        build: (_) => [
          pw.Text(company.name, style: pw.TextStyle(font: bold, fontSize: 16)),
          pw.SizedBox(height: 4),
          pw.Text(
            'reports.unapplied_advances_report'.tr(),
            style: pw.TextStyle(
              font: bold,
              fontSize: 18,
              color: PdfColors.blue700,
            ),
          ),
          pw.Text(
            '${'reports.report_as_of'.tr()}: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
            style: cellStyle,
          ),
          pw.SizedBox(height: 12),
          ...summaries.map(
            (summary) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Text(
                '${summary.currencyCode}: '
                '${'reports.customer_advances'.tr()} ${_money(summary.currencySymbol, summary.customerCents)} · '
                '${'reports.supplier_advances'.tr()} ${_money(summary.currencySymbol, summary.supplierCents)}',
                style: pw.TextStyle(font: bold, fontSize: 10),
              ),
            ),
          ),
          pw.SizedBox(height: 8),
          if (rows.isEmpty)
            pw.Text(
              'reports.no_unapplied_advances'.tr(),
              style: pw.TextStyle(font: regular, fontSize: 11),
            )
          else
            pw.TableHelper.fromTextArray(
              headers: [
                'reports.advance_party_type'.tr(),
                'reports.advance_party'.tr(),
                'reports.advance_cheque_number'.tr(),
                'reports.advance_recognized_date'.tr(),
                'reports.advance_currency'.tr(),
                'reports.advance_original_amount'.tr(),
                'reports.advance_applied_amount'.tr(),
                'reports.advance_unapplied_amount'.tr(),
              ],
              data: rows
                  .map(
                    (row) => [
                      _partyTypeLabel(row.partyType),
                      row.partyName,
                      row.chequeNumber,
                      DateFormat('dd/MM/yyyy').format(row.recognizedAt),
                      row.currencyCode,
                      _money(row.currencySymbol, row.amountCents),
                      _money(row.currencySymbol, row.appliedCents),
                      _money(row.currencySymbol, row.unappliedCents),
                    ],
                  )
                  .toList(growable: false),
              headerStyle: headerStyle,
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.blue700,
              ),
              cellStyle: cellStyle,
              cellAlignment: pw.Alignment.centerRight,
              border: pw.TableBorder.all(color: PdfColors.grey300, width: .5),
              cellPadding: const pw.EdgeInsets.all(5),
            ),
        ],
      ),
    );
    return document;
  }

  static String _partyTypeLabel(String partyType) => partyType == 'customer'
      ? 'reports.advance_customer'.tr()
      : 'reports.advance_supplier'.tr();

  static String _money(String symbol, int cents) =>
      '$symbol${(cents / 100).toStringAsFixed(2)}';

  static String _filename(String extension) =>
      'UnappliedAdvances_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.$extension';
}
