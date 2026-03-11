import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' hide TextDirection;
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:ui' as ui;

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../../settings/data/services/company_profile_service.dart';

class _PdfFonts {
  final pw.Font regular;
  final pw.Font bold;
  _PdfFonts({required this.regular, required this.bold});
}

class PaymentRemindersPdfService {
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

  static Future<void> printPaymentReminders({required BuildContext context}) async {
    // Capture RTL before async gap
    final textDir = Directionality.of(context);
    final isRtl = textDir == ui.TextDirection.rtl;
    final dir = isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    
    final db = sl<AppDatabase>();
    final cs = sl<CurrencyService>();
    final company = await sl<CompanyProfileService>().getProfile();
    final fonts = await _loadFonts();

    // Fetch customers with outstanding balances
    final customersData = await db.customSelect(
      '''
      SELECT 
        id,
        name,
        phone,
        email,
        balance_cents
      FROM customers
      WHERE balance_cents > 0
      ORDER BY balance_cents DESC
      ''',
      readsFrom: {db.customers},
    ).get();

    // Fetch suppliers with outstanding balances (we owe them)
    final suppliersData = await db.customSelect(
      '''
      SELECT 
        id,
        name,
        phone,
        email,
        balance_cents
      FROM suppliers
      WHERE balance_cents < 0
      ORDER BY balance_cents ASC
      ''',
      readsFrom: {db.suppliers},
    ).get();

    final pdf = pw.Document();

    // Calculate totals
    int totalCustomerBalance = 0;
    int totalSupplierBalance = 0;

    for (final row in customersData) {
      totalCustomerBalance += row.read<int>('balance_cents');
    }

    for (final row in suppliersData) {
      totalSupplierBalance += row.read<int>('balance_cents').abs();
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        textDirection: dir,
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: dir,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header
                pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.amber50,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        company.name,
                        style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, font: fonts.bold),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'dashboard.payment_reminders'.tr(),
                        style: pw.TextStyle(fontSize: 14, color: PdfColors.amber800, font: fonts.regular),
                      ),
                      pw.Text(
                        DateFormat('EEEE, MMMM d, yyyy').format(DateTime.now()),
                        style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700, font: fonts.regular),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 20),

                // Summary
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Column(
                    children: [
                      _buildSummaryRow(
                        'dashboard.customers_owe'.tr(),
                        '${customersData.length} ${'dashboard.accounts'.tr()}',
                        cs.format(totalCustomerBalance),
                        PdfColors.green,
                        fonts,
                      ),
                      pw.Divider(),
                      _buildSummaryRow(
                        'dashboard.suppliers_owed'.tr(),
                        '${suppliersData.length} ${'dashboard.accounts'.tr()}',
                        cs.format(totalSupplierBalance),
                        PdfColors.red,
                        fonts,
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 20),

                // Customers section
                if (customersData.isNotEmpty) ...[
                  pw.Text(
                    'dashboard.customers_owe'.tr(),
                    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.green, font: fonts.bold),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey300),
                    children: [
                      // Header
                      pw.TableRow(
                        decoration: pw.BoxDecoration(color: PdfColors.green.shade(0.1)),
                        children: [
                          _buildTableCell('customers.name'.tr(), fonts, isHeader: true),
                          _buildTableCell('customers.phone'.tr(), fonts, isHeader: true),
                          _buildTableCell('customers.email'.tr(), fonts, isHeader: true),
                          _buildTableCell('customers.balance'.tr(), fonts, isHeader: true),
                        ],
                      ),
                      // Data rows
                      ...customersData.map((row) {
                        final name = row.read<String>('name');
                        final phone = row.readNullable<String>('phone') ?? '-';
                        final email = row.readNullable<String>('email') ?? '-';
                        final balance = row.read<int>('balance_cents');

                        return pw.TableRow(
                          children: [
                            _buildTableCell(name, fonts),
                            _buildTableCell(phone, fonts),
                            _buildTableCell(email, fonts),
                            _buildTableCell(cs.format(balance), fonts, align: pw.TextAlign.right),
                          ],
                        );
                      }),
                    ],
                  ),
                  pw.SizedBox(height: 20),
                ],

                // Suppliers section
                if (suppliersData.isNotEmpty) ...[
                  pw.Text(
                    'dashboard.suppliers_owed'.tr(),
                    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.red, font: fonts.bold),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey300),
                    children: [
                      // Header
                      pw.TableRow(
                        decoration: pw.BoxDecoration(color: PdfColors.red.shade(0.1)),
                        children: [
                          _buildTableCell('suppliers.name'.tr(), fonts, isHeader: true),
                          _buildTableCell('suppliers.phone'.tr(), fonts, isHeader: true),
                          _buildTableCell('suppliers.email'.tr(), fonts, isHeader: true),
                          _buildTableCell('suppliers.balance'.tr(), fonts, isHeader: true),
                        ],
                      ),
                      // Data rows
                      ...suppliersData.map((row) {
                        final name = row.read<String>('name');
                        final phone = row.readNullable<String>('phone') ?? '-';
                        final email = row.readNullable<String>('email') ?? '-';
                        final balance = row.read<int>('balance_cents').abs();

                        return pw.TableRow(
                          children: [
                            _buildTableCell(name, fonts),
                            _buildTableCell(phone, fonts),
                            _buildTableCell(email, fonts),
                            _buildTableCell(cs.format(balance), fonts, align: pw.TextAlign.right),
                          ],
                        );
                      }),
                    ],
                  ),
                ],

                pw.Spacer(),

                // Footer
                pw.Container(
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    '${'dashboard.generated_on'.tr()}: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
                    style: pw.TextStyle(fontSize: 8, color: PdfColors.grey500, font: fonts.regular),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

  static pw.Widget _buildSummaryRow(
    String label,
    String count,
    String amount,
    PdfColor color,
    _PdfFonts fonts,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Text(
              label,
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, font: fonts.bold),
            ),
          ),
          pw.Text(
            count,
            style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700, font: fonts.regular),
          ),
          pw.SizedBox(width: 20),
          pw.Text(
            amount,
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: color, font: fonts.bold),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildTableCell(
    String text,
    _PdfFonts fonts, {
    bool isHeader = false,
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isHeader ? 10 : 9,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
          font: isHeader ? fonts.bold : fonts.regular,
        ),
        textAlign: align,
        maxLines: 2,
        overflow: pw.TextOverflow.clip,
      ),
    );
  }
}
