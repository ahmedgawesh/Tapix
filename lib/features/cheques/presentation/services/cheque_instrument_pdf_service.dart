import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../../core/database/daos/cheque_instrument_dao.dart';
import '../../../../core/services/cheque_management_service.dart';
import '../../../../core/utils/app_date_formatter.dart';

/// Prints the physical cheque itself, independently from party payments.
/// An open instrument is explicitly a cheque memo; only a cleared instrument
/// is titled as a payment document.
class ChequeInstrumentPdfService {
  static Future<void> printDocument({
    required BuildContext context,
    required ChequeRegisterEntry entry,
  }) async {
    final pdf = await _build(context, entry);
    await Printing.layoutPdf(
      name: _filename(entry),
      onLayout: (_) => pdf.save(),
    );
  }

  static Future<void> shareDocument({
    required BuildContext context,
    required ChequeRegisterEntry entry,
  }) async {
    final pdf = await _build(context, entry);
    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: _filename(entry),
    );
  }

  static String _filename(ChequeRegisterEntry entry) {
    final number = entry.instrument.chequeNumber?.trim();
    return 'CHEQUE-${number?.isNotEmpty == true ? number : entry.instrument.id}.pdf';
  }

  static Future<pw.Document> _build(
    BuildContext context,
    ChequeRegisterEntry entry,
  ) async {
    final locale = context.locale;
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/IBMPlexSansArabic-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/IBMPlexSansArabic-Bold.ttf'),
    );
    final rtl = locale.languageCode == 'ar';
    final c = entry.instrument;
    final incoming = c.direction == ChequeDirectionValue.incoming;
    final cleared = c.status == ChequeInstrumentStatus.cleared;
    final title = cleared
        ? (incoming
              ? 'cheques.pdf_payment_received_title'.tr()
              : 'cheques.pdf_payment_issued_title'.tr())
        : (incoming
              ? 'cheques.pdf_incoming_title'.tr()
              : 'cheques.pdf_outgoing_title'.tr());
    final amount =
        '${entry.currencySymbol}${(c.amountCents.toBigInt().toInt() / 100).toStringAsFixed(2)}';
    final pdf = pw.Document();
    pw.Widget text(String value, {bool strong = false, double size = 11}) =>
        pw.Text(
          value,
          style: pw.TextStyle(font: strong ? bold : regular, fontSize: size),
        );
    pw.Widget row(String label, String value) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          text(label),
          pw.SizedBox(width: 16),
          pw.Expanded(child: text(value, strong: true)),
        ],
      ),
    );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        textDirection: rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.all(18),
              color: cleared ? PdfColors.blue50 : PdfColors.orange50,
              child: text(title, strong: true, size: 22),
            ),
            pw.SizedBox(height: 24),
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                children: [
                  row('cheques.number'.tr(), c.chequeNumber ?? '—'),
                  row('cheques.document'.tr(), entry.referenceNumber),
                  row('cheques.party'.tr(), entry.partyName ?? '—'),
                  row('cheques.status'.tr(), 'cheques.status_${c.status}'.tr()),
                  if (c.bankName?.trim().isNotEmpty == true)
                    row('cheques.bank'.tr(), c.bankName!),
                  if (c.issueDate != null)
                    row(
                      'cheques.issue_date'.tr(),
                      AppDateFormatter.date(c.issueDate!),
                    ),
                  row(
                    'cheques.due_date'.tr(),
                    AppDateFormatter.date(c.dueDate),
                  ),
                  if (c.note?.trim().isNotEmpty == true)
                    row('cheques.note'.tr(), c.note!),
                ],
              ),
            ),
            pw.SizedBox(height: 24),
            pw.Container(
              padding: const pw.EdgeInsets.all(20),
              color: PdfColors.blue50,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  text('cheques.amount'.tr(), strong: true, size: 14),
                  text(amount, strong: true, size: 21),
                ],
              ),
            ),
            pw.Spacer(),
            text('cheques.pdf_lifecycle_notice'.tr(), size: 9),
          ],
        ),
      ),
    );
    return pdf;
  }
}
